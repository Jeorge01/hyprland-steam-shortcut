#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

HYPR_BLUE=$'\e[38;2;94;204;227m'
HYPR_DARK_BLUE=$'\e[38;2;85;184;204m'
HYPR_DARKEST_BLUE=$'\e[38;2;72;162;180m'

GREEN=$'\e[38;2;94;227;149m'
YELLOW=$'\e[38;2;244;208;63m'
RED=$'\e[38;2;231;76;60m'
WHITE=$'\e[1;37m'
GRAY_BG=$'\e[48;2;42;42;42m'
WHITE_FG=$'\e[38;2;255;255;255m'
K_DIM=$'\e[38;2;97;97;97m'
K_DIM2=$'\e[38;2;73;73;73m'
RESET_ALL=$'\e[0m'
CLEAR=$'\e[0m'

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/steam-shortcut"
DEVICES_DIR="$CONFIG_DIR/devices"

APP_DIR="$HOME/.local/share/hss"
HSS_BIN="$HOME/.local/bin/hss"

RAW_URL="${HSS_RAW_URL:-https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main}"
HSS_URL="$RAW_URL/bind-manager.sh"
UNINSTALL_URL="$RAW_URL/uninstall.sh"
RUN_URL="$RAW_URL/run_steam.sh"

declare -a INSTALLED=()

log_info() {
    echo "$1" | fmt -w 57 | sed 's/^/   /'
}

run_cmd() {
    local output
    output=$("$@" 2>&1)
    if [ $? -ne 0 ]; then
        echo "$output" | fmt -w 54 | sed 's/^/      /'
        return 1
    fi
    return 0
}

# -------------------------------------------------------------------------
# STEP 1: PRE-FLIGHT CHECKS & DISTRO DETECTION (FAIL-FAST)
# -------------------------------------------------------------------------

if [ "$(id -u)" = "0" ]; then
    echo -e "${YELLOW}⚠️ Do not run this script with 'sudo' or as root directly.${CLEAR}"
    echo -e "${YELLOW}   Run it as a regular user. The script will ask for sudo when needed.${CLEAR}"
    exit 1
fi

# Batch validation: system requirements
ERRORS=()

if ! command -v systemctl &> /dev/null; then
    ERRORS+=("systemd (systemctl) not found — required for systemd user service")
fi

if command -v pacman &> /dev/null; then
    DISTRO="󰣇 Arch"
    PKG_MANAGER="pacman"
elif command -v dnf &> /dev/null; then
    DISTRO=" Fedora"
    PKG_MANAGER="dnf"
else
    ERRORS+=("Unsupported distribution — endast Arch (pacman) och Fedora (dnf)")
fi

if ! command -v hyprctl &> /dev/null; then
    ERRORS+=("Hyprland (hyprctl) not found — required for workspace focus")
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}❌ Setup cannot continue:${CLEAR}"
    for err in "${ERRORS[@]}"; do
        echo -e "${RED}   • ${err}${CLEAR}"
    done
    exit 1
fi

if ! command -v steam &> /dev/null; then
    echo -e "${RED}❌ ERROR: Steam is missing from your system.${CLEAR}"
    echo -e "${RED}   Please install Steam first before running this installation script.${CLEAR}"
    exit 1
fi

# -------------------------------------------------------------------------
# INSTALL PLAN & CONFIRMATION
# -------------------------------------------------------------------------

build_plan() {
    PLAN_PKGS=()
    PLAN_SYS=()
    PLAN_SKIP=()

    if ! command -v gum &>/dev/null; then
        PLAN_PKGS+=("gum — interactive prompt UI")
    else
        PLAN_SKIP+=("gum — interactive prompt UI (already installed)")
    fi

    if command -v evtest &> /dev/null; then
        PLAN_SKIP+=("evtest — controller input capture (already installed)")
    else
        PLAN_PKGS+=("evtest — controller input capture")
    fi

    if [ -f "/etc/modules-load.d/xpad.conf" ]; then
        PLAN_SKIP+=("xpad driver — auto-load on boot (already configured)")
    else
        PLAN_SYS+=("xpad driver — auto-load on boot")
    fi

    if [ -f "$HOME/.config/systemd/user/xbox-steam.service" ] || \
       [ -f /etc/systemd/system/xbox-steam.service ] || \
       systemctl is-enabled xbox-steam.service &>/dev/null; then
        PLAN_SYS+=("Remove legacy single-device xbox-steam service")
    fi

    PLAN_SYS+=("systemd template unit — xbox-steam@.service")
    PLAN_SYS+=("loginctl linger — run listener without login session")
    PLAN_SYS+=("sudoers rule — passwordless evtest (/etc/sudoers.d/xbox-steam-evtest)")
    PLAN_SYS+=("evtest cleanup helper — /usr/local/sbin/hss-evtest-stop")
    PLAN_SYS+=("Bind Manager — ~/.local/share/hss/bind-manager.sh")
    PLAN_SYS+=("Uninstaller — ~/.local/share/hss/uninstall.sh")
    PLAN_SYS+=("Steam launcher — ~/.local/share/hss/run_steam.sh")
    PLAN_SYS+=("Launcher — ~/.local/bin/hss")
}

confirm_install() {
    build_plan

    echo ""
    echo -e "  ${HYPR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
    echo -e "  ${HYPR_BLUE}󰦐  Installation plan${CLEAR}"
    echo -e "  ${HYPR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"

    if [ ${#PLAN_PKGS[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${WHITE}Software packages (via ${PKG_MANAGER}):${CLEAR}"
        for item in "${PLAN_PKGS[@]}"; do
            echo -e "  ${GREEN}󰄾${CLEAR} ${item}"
        done
    fi

    echo ""
    echo -e "  ${WHITE}System configuration & files:${CLEAR}"
    for item in "${PLAN_SYS[@]}"; do
        echo -e "  ${GREEN}󰄾${CLEAR} ${item}"
    done

    if [ ${#PLAN_SKIP[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${K_DIM}Already installed — will be skipped:${CLEAR}"
        for item in "${PLAN_SKIP[@]}"; do
            echo -e "  ${K_DIM}󰄾${CLEAR} ${item}"
        done
    fi

    echo ""
    echo -e "  ${YELLOW}Install the above? [Y/n]${CLEAR}"
    printf '\033[?25l' >/dev/tty
    read -r -s -n1 answer </dev/tty || true
    printf '\033[?25h' >/dev/tty
    echo ""
    case "$answer" in
        ""|y|Y)
            echo -e "  ${GREEN}Proceeding with installation...${CLEAR}"
            echo ""
            ;;
        *)
            echo -e "  ${YELLOW}Installation cancelled — nothing was installed.${CLEAR}"
            exit 0
            ;;
    esac
}

confirm_install

USER_NAME=$(id -un)
USER_ID=$(id -u)

sudo -v </dev/tty || exit 1
while true; do sudo -n true; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!

# -------------------------------------------------------------------------
# STEP 2: DEPENDENCIES
# -------------------------------------------------------------------------

# Install gum for interactive menu
if ! command -v gum &>/dev/null; then
    echo -e "${YELLOW}  gum not found — installing for better UI...${CLEAR}"
    if [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S --needed --noconfirm gum
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        sudo dnf install -y gum
    fi
    INSTALLED+=("gum — interactive prompt UI")
fi

if command -v evtest &> /dev/null; then
    echo "  evtest is already installed, skipping..."
else
    echo "  evtest is missing. Installing via $PKG_MANAGER..."
    if [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S --needed --noconfirm evtest
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        sudo dnf install -y evtest
    fi
    INSTALLED+=("evtest — controller input capture")
fi

echo "  Configuring xpad driver..."
if [ -f "/etc/modules-load.d/xpad.conf" ]; then
    echo "  xpad is already configured for auto-load, skipping..."
else
    if ! lsmod | grep -q "xpad"; then
        echo "Loading xpad into the kernel..."
        sudo modprobe xpad || log_info "[!] Failed to load xpad module"
    fi
    echo "Setting xpad to load automatically on boot..."
    echo "xpad" | sudo tee /etc/modules-load.d/xpad.conf > /dev/null
    INSTALLED+=("xpad driver — auto-load on boot")
fi

# -------------------------------------------------------------------------
# STEP 3: SYSTEMD SERVICE
# -------------------------------------------------------------------------

install_service_unit() {
    mkdir -p "$HOME/.config/systemd/user"

    log_info "Creating/Updating systemd template unit (xbox-steam@.service)..."
    cat << EOF > "$HOME/.config/systemd/user/xbox-steam@.service"
[Unit]
Description=Steam Big Picture Trigger (%i)
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash $APP_DIR/run_steam.sh listen %i
ExecStop=/bin/sh -c 'pid_file="/tmp/xbox-steam-%i-pids.txt"; nodes_file="/tmp/xbox-steam-%i-nodes.txt"; if [ -f "\$pid_file" ]; then xargs kill < "\$pid_file" 2>/dev/null; rm -f "\$pid_file"; fi; if [ -f "\$nodes_file" ]; then sudo -n /usr/local/sbin/hss-evtest-stop \$(cat "\$nodes_file") 2>/dev/null || true; rm -f "\$nodes_file"; fi'
KillMode=control-group
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
    INSTALLED+=("systemd template unit — ${HYPR_BLUE}xbox-steam@.service${CLEAR}")

    log_info "Reloading systemd configuration..."
    if ! run_cmd systemctl --user daemon-reload; then
        log_info "[!] Failed to reload systemd configuration."
    fi

    log_info "Ensuring background execution via lingering..."
    if run_cmd loginctl enable-linger "$USER_NAME"; then
        log_info "Lingering enabled for $USER_NAME."
        INSTALLED+=("loginctl linger — listener runs without login session")
    fi
}

remove_legacy_service() {
    if [ -f "$HOME/.config/systemd/user/xbox-steam.service" ]; then
        echo "󰃢  Cleaning up the old single-device service..."
        systemctl --user disable --now xbox-steam.service 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/xbox-steam.service"
    fi
    if systemctl is-enabled xbox-steam.service &>/dev/null || [ -f /etc/systemd/system/xbox-steam.service ]; then
        echo "󰃢  Cleaning up the old global system service..."
        sudo systemctl disable --now xbox-steam.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/xbox-steam.service
        sudo systemctl daemon-reload
    fi
}

echo "󰃢  Removing any legacy single-device services..."
remove_legacy_service
install_service_unit

echo "  Adding sudoers rule for evtest..."
SU_FILE="/etc/sudoers.d/xbox-steam-evtest"
{
    echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/evtest"
    echo "$(id -un) ALL=(root) NOPASSWD: /usr/local/sbin/hss-evtest-stop"
} | sudo tee "$SU_FILE" > /dev/null
sudo chmod 440 "$SU_FILE"
INSTALLED+=("sudoers rule — passwordless evtest (${HYPR_BLUE}$SU_FILE${CLEAR})")

echo "  Installing evtest cleanup helper..."
sudo tee /usr/local/sbin/hss-evtest-stop > /dev/null << 'EOF'
#!/bin/bash
# hss-evtest-stop — kill evtest listeners attached to the given input event
# nodes. Runs as root via sudo (NOPASSWD). The bind listener runs evtest as
# root inside a user systemd service, whose cgroup the user manager cannot
# kill, so stopping a bind needs this explicit, scoped kill.
for node in "$@"; do
    case "$node" in
        event[0-9]*) ;;
        *) continue ;;
    esac
    pkill -f "evtest /dev/input/$node" 2>/dev/null
done
exit 0
EOF
sudo chmod 755 /usr/local/sbin/hss-evtest-stop
INSTALLED+=("evtest cleanup helper — ${HYPR_BLUE}/usr/local/sbin/hss-evtest-stop${CLEAR}")

# -------------------------------------------------------------------------
# STEP 4: DEPLOY FILES
# -------------------------------------------------------------------------

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

deploy_file() {
    local name="$1" dest="$2" url="$3"
    if [ -f "$SCRIPT_DIR/$name" ]; then
        log_info "Copying $name from local repo..."
        cp "$SCRIPT_DIR/$name" "$dest"
        return 0
    fi
    if command -v curl &>/dev/null; then
        log_info "Downloading $name..."
        if curl -sL "$url" -o "$dest"; then
            return 0
        fi
    fi
    return 1
}

mkdir -p "$APP_DIR" "$HOME/.local/bin"

if ! deploy_file "bind-manager.sh" "$APP_DIR/bind-manager.sh" "$HSS_URL"; then
    echo -e "${RED}❌ Failed to deploy bind-manager.sh — aborting.${CLEAR}"
    exit 1
fi
INSTALLED+=("Bind Manager — ${HYPR_BLUE}$APP_DIR/bind-manager.sh${CLEAR}")

if ! deploy_file "uninstall.sh" "$APP_DIR/uninstall.sh" "$UNINSTALL_URL"; then
    echo -e "${RED}❌ Failed to deploy uninstall.sh — aborting.${CLEAR}"
    exit 1
fi
INSTALLED+=("Uninstaller — ${HYPR_BLUE}$APP_DIR/uninstall.sh${CLEAR}")

if ! deploy_file "run_steam.sh" "$APP_DIR/run_steam.sh" "$RUN_URL"; then
    echo -e "${YELLOW}⚠️  Failed to deploy run_steam.sh — binds will not work until it is present.${CLEAR}"
else
    INSTALLED+=("Steam launcher — ${HYPR_BLUE}$APP_DIR/run_steam.sh${CLEAR}")
fi

chmod +x "$APP_DIR/bind-manager.sh" "$APP_DIR/uninstall.sh" "$APP_DIR/run_steam.sh"

# Verify the deployed scripts are real scripts (catches failed/404 downloads)
for f in bind-manager.sh uninstall.sh; do
    if [ ! -f "$APP_DIR/$f" ] || ! head -c 2 "$APP_DIR/$f" | grep -q '#!'; then
        echo -e "${RED}❌ $f was not deployed correctly (missing or corrupt) — aborting.${CLEAR}"
        exit 1
    fi
done

# hss launcher symlink
if [ -e "$HSS_BIN" ] && [ ! -L "$HSS_BIN" ]; then
    rm -f "$HSS_BIN"
fi
ln -sf "$APP_DIR/bind-manager.sh" "$HSS_BIN"
INSTALLED+=("Launcher — ${HYPR_BLUE}$HSS_BIN${CLEAR}")

# -------------------------------------------------------------------------
# STEP 5: NOTES
# -------------------------------------------------------------------------

# Conflict check: the 'hss' package (parallel SSH client) ships /usr/bin/hss
if [ -x /usr/bin/hss ]; then
    bin_prio=$(printf '%s\n' "$PATH" | tr ':' '\n' | awk -v t="$HOME/.local/bin" '$0==t{print NR; exit}')
    usr_prio=$(printf '%s\n' "$PATH" | tr ':' '\n' | awk -v t="/usr/bin" '$0==t{print NR; exit}')
    [ -z "$bin_prio" ] && bin_prio=9999
    [ -z "$usr_prio" ] && usr_prio=9999
    echo ""
    echo -e "${YELLOW}⚠️  Note: the 'hss' package (parallel SSH client) is installed at /usr/bin/hss.${CLEAR}"
    if [ "$bin_prio" -lt "$usr_prio" ]; then
        echo -e "${YELLOW}   Your ~/.local/bin comes first in PATH, so 'hss' now opens this Bind Manager.${CLEAR}"
        echo -e "${YELLOW}   The SSH client is shadowed — run it with its full path (/usr/bin/hss).${CLEAR}"
    else
        echo -e "${YELLOW}   /usr/bin comes first in PATH, so 'hss' runs the SSH client.${CLEAR}"
        echo -e "${YELLOW}   Open this Bind Manager with '${HYPR_BLUE}~/.local/bin/hss${CLEAR}${YELLOW}' instead.${CLEAR}"
    fi
fi

case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *)
        echo ""
        echo -e "${YELLOW}⚠️  ~/.local/bin is not in your PATH.${CLEAR}"
        echo -e "${YELLOW}   Add it (e.g. 'export PATH=\"\$HOME/.local/bin:\$PATH\"' in ~/.bashrc) or run '${HYPR_BLUE}~/.local/bin/hss${CLEAR}${YELLOW}'.${CLEAR}"
        ;;
esac

echo ""
echo -e "  ${HYPR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
echo -e "  ${HYPR_BLUE}  Installed components${CLEAR}"
echo -e "  ${HYPR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CLEAR}"
for item in "${INSTALLED[@]}"; do
    echo -e "  ${GREEN}󰄾${CLEAR} ${item}"
done
echo ""
echo -e "  ${GREEN}Installation complete.${CLEAR}"
echo -e "  Run '${HYPR_BLUE}hss${CLEAR}' anytime to open the Bind Manager."
echo ""

echo -e "  ${K_DIM}enter${CLEAR} ${K_DIM2}continue${CLEAR}"
printf '\033[?25l' >/dev/tty
read -r -s -n1 </dev/tty || true
printf '\033[?25h' >/dev/tty
echo ""

echo "  Starting Bind Manager..."
exec "$HSS_BIN"
