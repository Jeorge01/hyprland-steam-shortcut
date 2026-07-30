#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Version (auto-detected from file modification date)
VERSION=$(stat -c %y "$0" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

HYPR_BLUE=$'\e[38;2;94;204;227m'
HYPR_DARK_BLUE=$'\e[38;2;85;184;204m'
HYPR_DARKEST_BLUE=$'\e[38;2;72;162;180m'

GREEN=$'\e[38;2;94;227;149m'
DARK_GREEN=$'\e[38;2;85;204;134m'
DARKEST_GREEN=$'\e[38;2;72;180;117m'

YELLOW=$'\e[38;2;244;208;63m'
RED=$'\e[38;2;231;76;60m'
BLUE=$'\e[38;2;52;152;219m'
CYAN=$'\e[38;2;26;188;156m'
WHITE=$'\e[1;37m'
GRAY_BG=$'\e[48;2;42;42;42m'
WHITE_FG=$'\e[38;2;255;255;255m'
RESET_ALL=$'\e[0m'
CLEAR=$'\e[0m'

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

choose() {
    if command -v gum &>/dev/null; then
        gum choose --header "" --selected.foreground "#5ECCDF" --cursor.foreground "#5ECCDF" "$@" </dev/tty
    else
        local opts=()
        local i=1
        for opt in "$@"; do
            echo -e "  [${WHITE}${i}${CLEAR}] $opt"
            opts+=("$opt")
            ((i++))
        done
        echo ""
        echo -e -n "  Select option: "
        read -r choice </dev/tty
        echo "${opts[$((choice-1))]}"
    fi
}

confirm() {
    if command -v gum &>/dev/null; then
        gum confirm "$1" </dev/tty \
            --prompt.foreground "#E74C3C" \
            --selected.foreground "#FFFFFF" \
            --selected.background "#E74C3C" \
            --unselected.foreground "#CCCCCC" \
            --unselected.background "#2A2A2A" \
            --affirmative " Yes " \
            --negative " No "
    else
        echo -n "$1 (y/n): "
        read -r r </dev/tty
        [[ "$r" =~ ^[Yy]$ ]]
    fi
}

echo -e ""
echo -e "${HYPR_BLUE}"

printf "%b" "$(cat << EOF
▖▖    ${HYPR_DARK_BLUE}  ▜   ${HYPR_DARKEST_BLUE}   ▌${HYPR_BLUE}  ▄▖▗ ${HYPR_DARK_BLUE}    ${HYPR_DARKEST_BLUE}   ${HYPR_BLUE}  ▄▖▌ ${HYPR_DARK_BLUE}    ▗ ${HYPR_DARKEST_BLUE}    ▗ ${HYPR_BLUE}
▙▌▌▌▛▌${HYPR_DARK_BLUE}▛▘▐ ▀▌${HYPR_DARKEST_BLUE}▛▌▛▌${HYPR_BLUE}  ▚ ▜▘${HYPR_DARK_BLUE}█▌▀▌${HYPR_DARKEST_BLUE}▛▛▌${HYPR_BLUE}  ▚ ▛▌${HYPR_DARK_BLUE}▛▌▛▘▜▘${HYPR_DARKEST_BLUE}▛▘▌▌▜▘${HYPR_BLUE}
▌▌▙▌▙▌${HYPR_DARK_BLUE}▌ ▐▖█▌${HYPR_DARKEST_BLUE}▌▌▙▌${HYPR_BLUE}  ▄▌▐▖${HYPR_DARK_BLUE}▙▖█▌${HYPR_DARKEST_BLUE}▌▌▌${HYPR_BLUE}  ▄▌▌▌${HYPR_DARK_BLUE}▙▌▌ ▐▖${HYPR_DARKEST_BLUE}▙▖▙▌▐▖${HYPR_BLUE}
  ▄▌▌  ${HYPR_BLUE}In${HYPR_DARK_BLUE}st${HYPR_DARKEST_BLUE}all${HYPR_BLUE} scr${HYPR_DARK_BLUE}ipt${HYPR_BLUE}
EOF
)"

echo -e "${CLEAR}"
echo -e ""

# Handle --version flag
if [ "${1:-}" = "--version" ]; then
    echo "Latest update: ${VERSION}"
    exit 0
fi

# Handle flags
if [ "${1:-}" = "--status" ]; then
    if systemctl --user is-active --quiet xbox-steam.service 2>/dev/null; then
        echo -e "  ${GREEN}●${CLEAR} Service:    running"
    else
        echo -e "  ${RED}●${CLEAR} Service:    not running"
    fi

    echo -e "    Version:    ${WHITE}${VERSION}${CLEAR}"

    if [ -f "$HOME/run_steam.sh" ]; then
        DEVICE=$(grep "^TARGET_DEV_NAME=" "$HOME/run_steam.sh" | cut -d'"' -f2)
        MODE=$(grep "^BIND_MODE=" "$HOME/run_steam.sh" | cut -d'"' -f2)
        echo -e "    Device:     ${WHITE}${DEVICE:-unknown}${CLEAR}"

        if [ "$MODE" = "combo" ]; then
            MOD=$(grep "^MODIFIER_BTN_NAME=" "$HOME/run_steam.sh" | cut -d'"' -f2)
            TRG=$(grep "^TRIGGER_BTN_NAME=" "$HOME/run_steam.sh" | cut -d'"' -f2)
            echo -e "    Mode:       ${WHITE}combo${CLEAR}"
            echo -e "    Combo:      ${WHITE}${MOD} + ${TRG}${CLEAR}"
        else
            BUTTON=$(grep "^TARGET_BTN_NAME=" "$HOME/run_steam.sh" | cut -d'"' -f2)
            echo -e "    Mode:       ${WHITE}single${CLEAR}"
            echo -e "    Button:     ${WHITE}${BUTTON:-unknown}${CLEAR}"
        fi
    else
        echo -e "    ${YELLOW}No installation found.${CLEAR}"
    fi

    if [ -f /tmp/xbox-steam-pids.txt ] && [ -s /tmp/xbox-steam-pids.txt ]; then
        echo -e "    Listener:   ${GREEN}active${CLEAR}"
    else
        echo -e "    Listener:   ${YELLOW}inactive${CLEAR}"
    fi

    exit 0
fi

sudo -v </dev/tty || exit 1
while true; do sudo -n true; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!

cleanup() {
    printf '\033[?25h' >/dev/tty 2>/dev/null || true
    stty echo </dev/tty 2>/dev/null || true

    if [ -f /tmp/xbox-steam-calibrating ]; then
        rm -f /tmp/xbox-steam-calibrating
        if [ "${SERVICE_WAS_ACTIVE:-0}" -eq 1 ]; then
            systemctl --user start xbox-steam.service 2>/dev/null || true
        fi
    fi

    kill $(jobs -p) 2>/dev/null || true
    kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true
}

trap cleanup EXIT

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
    echo -e "${RED}❌ Installation cannot continue:${CLEAR}"
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

USER_NAME=$(id -un)
USER_ID=$(id -u)

# Install gum for interactive menu
if ! command -v gum &>/dev/null; then
    echo -e "${YELLOW}  gum not found — installing for better UI...${CLEAR}"
    if [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S --needed --noconfirm gum
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        sudo dnf install -y gum
    fi
fi
CHOICE=$(choose "  Bind device — Install and calibrate button trigger" "  Unbind — Remove existing installation")

if [[ "$CHOICE" == *"Unbind"* ]]; then
    echo ""

    # Check if anything is installed
    HAS_INSTALL=0
    systemctl --user is-enabled xbox-steam.service &>/dev/null && HAS_INSTALL=1
    [ -f "$HOME/.config/systemd/user/xbox-steam.service" ] && HAS_INSTALL=1
    [ -f "/etc/sudoers.d/xbox-steam-evtest" ] && HAS_INSTALL=1
    [ -f "$HOME/run_steam.sh" ] && HAS_INSTALL=1

    if [ "$HAS_INSTALL" -eq 0 ]; then
        echo -e "${YELLOW}Nothing to remove — no installation found.${CLEAR}"
        exit 0
    fi

    echo -e "${YELLOW}This will remove:${CLEAR}"
    echo -e "  - systemd service (xbox-steam.service)"
    echo -e "  - sudoers rule (/etc/sudoers.d/xbox-steam-evtest)"
    echo -e "  - automation script (~/run_steam.sh)"
    echo -e "  - log file (~/steam_error.log)"
    echo ""

    if ! confirm "Are you sure?"; then
        echo -e "${YELLOW}Aborted.${CLEAR}"
        exit 0
    fi

    echo -e "${YELLOW}Removing hyprland-steam-shortcut...${CLEAR}"
    
    systemctl --user stop xbox-steam.service 2>/dev/null || true
    systemctl --user disable xbox-steam.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/xbox-steam.service"
    systemctl --user daemon-reload 2>/dev/null || true
    
    sudo rm -f /etc/sudoers.d/xbox-steam-evtest
    
    rm -f "$HOME/run_steam.sh"
    rm -f "$HOME/steam_error.log"
    
    if [ -f /tmp/xbox-steam-pids.txt ]; then
        xargs kill < /tmp/xbox-steam-pids.txt 2>/dev/null || true
        rm -f /tmp/xbox-steam-pids.txt
    fi
    
    echo -e "${GREEN}Uninstalled successfully.${CLEAR}"
    exit 0
fi

if [[ "$CHOICE" != *"Bind"* ]]; then
    echo -e "${RED}No valid selection.${CLEAR}"
    exit 1
fi

# -------------------------------------------------------------------------
# STEP 2: DEPENDENCIES & DRIVERS
# -------------------------------------------------------------------------

echo -e "󰌽  Detected OS environment: ${HYPR_BLUE}${DISTRO}${CLEAR} (using ${PKG_MANAGER})"

if command -v evtest &> /dev/null; then
    echo "  evtest is already installed, skipping..."
else
    echo "  evtest is missing. Installing via $PKG_MANAGER..."
    if [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S --needed --noconfirm evtest
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        sudo dnf install -y evtest
    fi
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
fi

# -------------------------------------------------------------------------
# Stop input-remapper temporarily (it grabs all input devices and blocks evtest)
# -------------------------------------------------------------------------
if systemctl is-active --quiet input-remapper 2>/dev/null; then
    echo "⏸  input-remapper is running — stopping temporarily for calibration..."
    sudo systemctl stop input-remapper
fi

# -------------------------------------------------------------------------
# PAUSE SERVICE DURING CALIBRATION
# -------------------------------------------------------------------------
SERVICE_WAS_ACTIVE=0
if systemctl --user is-active --quiet xbox-steam.service 2>/dev/null; then
    SERVICE_WAS_ACTIVE=1
    log_info "Pausing active binds for calibration..."
    systemctl --user stop xbox-steam.service 2>/dev/null || true
    sudo pkill -f "[e]vtest" 2>/dev/null || true
fi
touch /tmp/xbox-steam-calibrating

restore_service() {
    printf '\033[?25h' >/dev/tty
    stty echo </dev/tty 2>/dev/null || true
    echo ""
    rm -f /tmp/xbox-steam-calibrating
    if [ "$SERVICE_WAS_ACTIVE" -eq 1 ]; then
        echo -e "${YELLOW}Calibration aborted. Restoring previous binds...${CLEAR}"
        systemctl --user start xbox-steam.service 2>/dev/null || true
        echo -e "${GREEN}Previous binds restored.${CLEAR}"
    else
        echo -e "${YELLOW}Calibration aborted.${CLEAR}"
    fi
    exit 0
}
trap restore_service INT TERM

# -------------------------------------------------------------------------
# COMBO-AWARE CALIBRATION (2-fas evtest)
# -------------------------------------------------------------------------
while true; do
if [ "${IS_REDO:-0}" -eq 0 ]; then
echo ""
echo -e "${HYPR_BLUE}  IN${HYPR_DARK_BLUE}PU${HYPR_DARKEST_BLUE}T${HYPR_BLUE} DE${HYPR_DARK_BLUE}VI${HYPR_DARKEST_BLUE}CE${HYPR_BLUE} CALI${HYPR_DARK_BLUE}BRAT${HYPR_DARKEST_BLUE}ION${HYPR_BLUE} RE${HYPR_DARK_BLUE}AD${HYPR_DARKEST_BLUE}Y${CLEAR}"
echo -e "   Before we begin, make sure your input device is turned ${GREEN}ON${CLEAR} and connected."
echo -e "   You will have ${YELLOW}60 seconds${CLEAR} to press a button."
echo -e "   Supports ${YELLOW}single${CLEAR} or ${YELLOW}combo${CLEAR} binds (hold first button + press second)."
echo ""
if command -v gum &>/dev/null; then
    if ! gum confirm "Ready to calibrate?" \
        --affirmative " Calibrate " \
        --negative " Cancel " \
        --prompt.foreground "#5ECCDF" \
        --selected.foreground "#FFFFFF" \
        --selected.background "#5ECCDF" \
        --unselected.foreground "#CCCCCC" \
        --unselected.background "#2A2A2A" \
        </dev/tty; then
        echo -e "${YELLOW}   Aborted.${CLEAR}"
        rm -f /tmp/xbox-steam-calibrating
        exit 0
    fi
else
    echo -n "Ready to calibrate? (y/n): "
    read -r r </dev/tty
    if [[ ! "$r" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}   Aborted.${CLEAR}"
        rm -f /tmp/xbox-steam-calibrating
        exit 0
    fi
fi
echo ""
fi

CALIB_EVTEST=$(mktemp)

set +e
for ev in /dev/input/event*; do
    if [ -r "$ev" ] || [ "$(id -u)" = "0" ] || command -v sudo &>/dev/null; then
        sudo stdbuf -oL timeout 70 evtest "$ev" 2>/dev/null | stdbuf -oL sed "s|^|$ev: |" >> "$CALIB_EVTEST" &
    fi
done

printf '\033[?25l' >/dev/tty
stty -echo </dev/tty 2>/dev/null || true
echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')Waiting for input...$(printf '%*s' 21 '')${RESET_ALL}"

CALIB_PHASE=1
CAPTURED_LINE=""
COMBO_RESULT=""
COMBO_BTN_CODE=""
COMBO_BTN_NAME=""

while IFS= read -r line; do
    if [ "$CALIB_PHASE" -eq 1 ]; then
        if echo "$line" | grep -q "code.*BTN_.*value 1"; then
            CAPTURED_LINE="$line"
            DETECTED_EV=$(echo "$line" | awk -F':' '{print $1}')
            FIRST_BTN_CODE=$(echo "$line" | grep -oP 'code \K[0-9]+')
            FIRST_BTN_NAME=$(echo "$line" | grep -oP 'BTN_[A-Z0-9]+')

            TARGET_DEV_NAME=$(awk -v RS='' '/Handlers=.*'"${DETECTED_EV##*/}"'( |$)/' /proc/bus/input/devices | grep -oP 'Name="\K[^"]+')
            [ -z "$TARGET_DEV_NAME" ] && TARGET_DEV_NAME="Generic Controller"

            echo -ne "\033[1A\033[2K\r"
            echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')Detected: ${FIRST_BTN_NAME}$(printf '%*s' $((31 - ${#FIRST_BTN_NAME})) '')${RESET_ALL}"
            echo ""
            echo -e -n "  Hold for ${YELLOW}combo${CLEAR}, or release for ${HYPR_BLUE}single${CLEAR} mode..."
            CALIB_PHASE=2
        fi
    else
        if [[ "$line" != "${DETECTED_EV}:"* ]]; then
            continue
        fi
        if echo "$line" | grep -q "code $FIRST_BTN_CODE .*value 0"; then
            COMBO_RESULT="single"
            break
        fi
        if echo "$line" | grep -q "code.*BTN_.*value 1"; then
            BTN_CODE=$(echo "$line" | grep -oP 'code \K[0-9]+')
            if [ "$BTN_CODE" != "$FIRST_BTN_CODE" ]; then
                COMBO_RESULT="combo"
                COMBO_BTN_CODE="$BTN_CODE"
                COMBO_BTN_NAME=$(echo "$line" | grep -oP 'BTN_[A-Z0-9]+')
            else
                COMBO_RESULT="single"
            fi
            break
        fi
    fi
done < <(timeout 70 tail -f -n +1 "$CALIB_EVTEST" 2>/dev/null)
printf '\033[?25h' >/dev/tty
stty echo </dev/tty 2>/dev/null || true
set -e

[[ -n "$(jobs -p)" ]] && kill $(jobs -p) 2>/dev/null || true
rm -f "$CALIB_EVTEST"

if [ -z "$CAPTURED_LINE" ]; then
    echo -ne "\033[1A\033[2K\r"
    echo -e "${RED}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"
    echo -ne "\033[2K\r"
    echo -e "${RED}│${CLEAR} ❌ ERROR: No input device activity detected within 60s.         ${RED}│${CLEAR}"
    echo -ne "\033[2K\r"
    echo -e "${RED}│${CLEAR}    Installation aborted. Please try again.                      ${RED}│${CLEAR}"
    echo -ne "\033[2K\r"
    echo -e "${RED}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
    echo -e ""
    echo -e "   ${YELLOW}Checking for conflicting processes...${CLEAR}"
    echo -e ""

    CONFLICT_FOUND=0
    if systemctl is-active --quiet input-remapper 2>/dev/null; then
        echo -e "   ${RED}●${CLEAR} input-remapper is running — ${YELLOW}sudo systemctl stop input-remapper${CLEAR}"
        CONFLICT_FOUND=1
    fi
    if pgrep -x "hkdm" > /dev/null 2>&1; then
        echo -e "   ${RED}●${CLEAR} hkdm is running — ${YELLOW}sudo pacman -R hkdm${CLEAR}"
        CONFLICT_FOUND=1
    fi

    HELD_BY=$(sudo fuser /dev/input/event* 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i+0==$i) print $i}' | sort -u)
    if [ -n "$HELD_BY" ]; then
        for PID in $HELD_BY; do
            PROC_NAME=$(cat /proc/$PID/comm 2>/dev/null || echo "unknown")
            echo -e "   ${RED}●${CLEAR} /dev/input/event* held by PID $PID ($PROC_NAME) — ${YELLOW}sudo kill -9 $PID${CLEAR}"
        done
        CONFLICT_FOUND=1
    fi

    if [ "$CONFLICT_FOUND" -eq 0 ]; then
        echo -e "   ${YELLOW}No obvious conflicts found.${CLEAR}"
        echo -e "   Make sure your controller is ${GREEN}ON${CLEAR} and ${GREEN}connected${CLEAR}."
    fi

    echo -e ""
    exit 1
fi

COMBO_FOUND=0

if [ "$COMBO_RESULT" = "combo" ]; then
    COMBO_FOUND=1
    BIND_MODE="combo"
    MODIFIER_BTN_CODE="$FIRST_BTN_CODE"
    MODIFIER_BTN_NAME="$FIRST_BTN_NAME"
    TRIGGER_BTN_CODE="$COMBO_BTN_CODE"
    TRIGGER_BTN_NAME="$COMBO_BTN_NAME"
else
    COMBO_FOUND=0
fi

if [ "$COMBO_FOUND" -eq 0 ]; then
    BIND_MODE="single"
    TARGET_BTN_CODE="$FIRST_BTN_CODE"
    TARGET_BTN_NAME="$FIRST_BTN_NAME"
fi

echo -ne "\033[2A\033[2K\r"
if [ "$BIND_MODE" = "combo" ]; then
    echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')${MODIFIER_BTN_NAME} + ${TRIGGER_BTN_NAME}$(printf '%*s' $((41 - ${#MODIFIER_BTN_NAME} - ${#TRIGGER_BTN_NAME})) '')${RESET_ALL}"
else
    echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')${TARGET_BTN_NAME}$(printf '%*s' $((41 - ${#TARGET_BTN_NAME})) '')${RESET_ALL}"
fi
echo -ne "\033[2K\r"
echo -ne "\033[2K\r"

echo ""
echo -e "${HYPR_BLUE}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"

VAL_COL=21

if [ "$BIND_MODE" = "combo" ]; then
    L3_VAL="$MODIFIER_BTN_NAME + $TRIGGER_BTN_NAME"
else
    L3_VAL="$TARGET_BTN_NAME (Code: $TARGET_BTN_CODE)"
fi

L2_TRAIL=$(printf '%*s' $((59 - VAL_COL - ${#TARGET_DEV_NAME})) '')
L3_TRAIL=$(printf '%*s' $((59 - VAL_COL - ${#L3_VAL})) '')
L4_TRAIL=$(printf '%*s' $((59 - VAL_COL - ${#BIND_MODE})) '')

COLOR_L1="${HYPR_BLUE}   Bu${HYPR_DARK_BLUE}tt${HYPR_DARKEST_BLUE}on${HYPR_BLUE} pr${HYPR_DARK_BLUE}es${HYPR_DARKEST_BLUE}s${HYPR_BLUE} det${HYPR_DARK_BLUE}ect${HYPR_DARKEST_BLUE}ed!${CLEAR}   $(printf '%*s' $((59 - 25)) '')"
COLOR_L2="${HYPR_BLUE}   Det${HYPR_DARK_BLUE}ect${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} De${HYPR_DARK_BLUE}vi${HYPR_DARKEST_BLUE}ce${HYPR_BLUE}:     ${CLEAR}${WHITE}${TARGET_DEV_NAME}${CLEAR}${L2_TRAIL}"
if [ "$BIND_MODE" = "combo" ]; then
    COLOR_L3="${HYPR_BLUE} 󰪥  Ma${HYPR_DARK_BLUE}pp${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} Co${HYPR_DARK_BLUE}mb${HYPR_DARKEST_BLUE}o${HYPR_BLUE}:        ${CLEAR}${WHITE}${L3_VAL}${CLEAR}${L3_TRAIL}"
else
    COLOR_L3="${HYPR_BLUE} 󰪥  Ma${HYPR_DARK_BLUE}pp${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} Bu${HYPR_DARK_BLUE}tt${HYPR_DARKEST_BLUE}on${HYPR_BLUE}:       ${CLEAR}${WHITE}${L3_VAL}${CLEAR}${L3_TRAIL}"
fi
COLOR_L4="${HYPR_BLUE}   Bi${HYPR_DARK_BLUE}nd${HYPR_DARKEST_BLUE} T${HYPR_BLUE}yp${HYPR_DARK_BLUE}e${HYPR_DARKEST_BLUE}:${CLEAR}           ${WHITE}${BIND_MODE}${CLEAR}${L4_TRAIL}"

echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L1}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L2}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L3}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L4}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"

# Blacklist check — prevent dangerous button bindings
BLACKLISTED_CODES="1 14 15 28 29 42 54 56 57 97 100 111 272 273 274 275 276 277 278"

if [ "$BIND_MODE" = "combo" ]; then
    CHECK_BTN_CODE="$TRIGGER_BTN_CODE"
    CHECK_BTN_NAME="$TRIGGER_BTN_NAME"
else
    CHECK_BTN_CODE="$TARGET_BTN_CODE"
    CHECK_BTN_NAME="$TARGET_BTN_NAME"
fi

for code in "$CHECK_BTN_CODE" "${MODIFIER_BTN_CODE:-}"; do
    [ -z "$code" ] && continue
    if echo "$BLACKLISTED_CODES" | grep -qw "$code"; then
        if [ "$code" = "$CHECK_BTN_CODE" ]; then
            name="$CHECK_BTN_NAME"
        else
            name="$MODIFIER_BTN_NAME"
        fi
        echo -e ""
        echo -e "${RED}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"
        echo -e "${RED}│${CLEAR} ❌ Button '${WHITE}${name}${CLEAR}' (code ${WHITE}${code}${CLEAR}) is blacklisted.                ${RED}│${CLEAR}"
        echo -e "${RED}│${CLEAR}    Binding this button would interfere with normal input.       ${RED}│${CLEAR}"
        echo -e "${RED}│${CLEAR}    Please choose a different button (e.g. Guide, Share, etc.)   ${RED}│${CLEAR}"
        echo -e "${RED}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
        echo -e ""
        exit 1
    fi
done

echo ""
BIND_CONFIRM=""
if command -v gum &>/dev/null; then
    if gum confirm "Want to use this bind?" \
        --affirmative " Use bind " \
        --negative " Redo " \
        --prompt.foreground "#5ECCDF" \
        --selected.foreground "#FFFFFF" \
        --selected.background "#5ECCDF" \
        --unselected.foreground "#CCCCCC" \
        --unselected.background "#2A2A2A" \
        </dev/tty; then
        BIND_CONFIRM="Use bind"
    else
        BIND_CONFIRM="Redo"
    fi
else
    echo -n "Want to use this bind? (y/n): "
    read -r r </dev/tty
    if [[ "$r" =~ ^[Yy]$ ]]; then
        BIND_CONFIRM="Use bind"
    else
        BIND_CONFIRM="Redo"
    fi
fi

if [[ "$BIND_CONFIRM" == *"Redo"* ]]; then
    echo -e "  ${YELLOW}Redoing calibration...${CLEAR}"
    echo -e ""
    IS_REDO=1
    continue
fi

break
done

trap - INT TERM
echo "─────────────────────────────────────────"

## -------------------------------------------------------------------------
# STEP 3: CREATE FILES & ACTIVATE
# -------------------------------------------------------------------------

rm -f /tmp/xbox-steam-calibrating

log_info "Creating/Updating automation script (~/run_steam.sh)..."
cat << EOF > "$HOME/run_steam.sh"
#!/bin/bash

# === CONFIGURATION (Auto-generated via Calibration) ===
USER_NAME="$USER_NAME"
USER_ID="$USER_ID"
TARGET_DEV_NAME="$TARGET_DEV_NAME"
BIND_MODE="$BIND_MODE"
TARGET_BTN_CODE="$TARGET_BTN_CODE"
TARGET_BTN_NAME="$TARGET_BTN_NAME"
MODIFIER_BTN_CODE="$MODIFIER_BTN_CODE"
MODIFIER_BTN_NAME="$MODIFIER_BTN_NAME"
TRIGGER_BTN_CODE="$TRIGGER_BTN_CODE"
TRIGGER_BTN_NAME="$TRIGGER_BTN_NAME"
# ======================================================

SCRIPT_PATH="\$(realpath "\$0")"

if [ "\$1" == "listen" ]; then
    echo "Starting listener..."

    while true; do
        until awk -v name="\$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=0} index(\$0, "N: Name=\"" name) == 1' /proc/bus/input/devices >/dev/null 2>&1; do
            echo "Waiting for your specific controller (\$TARGET_DEV_NAME) to initialize..."
            sleep 2
        done

        EVENT_NUMS=\$(awk -v name="\$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=0} index(\$0, "N: Name=\"" name) == 1 {cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if(\$i~/event/) print \$i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+')
        
        for NUM in \$EVENT_NUMS; do
            until [ -r "/dev/input/event\$NUM" ]; do
                echo "Waiting for /dev/input/event\$NUM to become readable..."
                sleep 0.2
            done
        done

        echo "Your calibrated device is ready! Initializing listener..."

        if systemctl is-active --quiet input-remapper 2>/dev/null; then
            echo "⚠️ WARNING: input-remapper is running and may block button detection"
            echo "   Run: sudo systemctl stop input-remapper"
        fi

        echo "" > /tmp/xbox-steam-pids.txt
        LISTENER_PIDS=""

        for NUM in \$EVENT_NUMS; do
            if [ -e "/dev/input/event\$NUM" ]; then
                echo "Listening on /dev/input/event\$NUM"
                (
                    sudo evtest /dev/input/event\$NUM 2>/dev/null | while read -r line; do
                        [ -f /tmp/xbox-steam-calibrating ] && continue
                        echo "[DEBUG-EV] \$line" >> "\$HOME/steam_error.log"
                        if [ "\$BIND_MODE" = "combo" ]; then
                            if echo "\$line" | grep -q "code \$MODIFIER_BTN_CODE.*value 1"; then
                                MODIFIER_HELD=1
                                echo "[DEBUG-COMBO] Modifier \$MODIFIER_BTN_NAME HELD (code \$MODIFIER_BTN_CODE)" >> "\$HOME/steam_error.log"
                            fi
                            if echo "\$line" | grep -q "code \$MODIFIER_BTN_CODE.*value 0"; then
                                MODIFIER_HELD=0
                                echo "[DEBUG-COMBO] Modifier \$MODIFIER_BTN_NAME RELEASED" >> "\$HOME/steam_error.log"
                            fi
                            if echo "\$line" | grep -q "code \$TRIGGER_BTN_CODE.*value 1"; then
                                echo "[DEBUG-COMBO] Trigger \$TRIGGER_BTN_NAME detected! MODIFIER_HELD=\${MODIFIER_HELD:-0}" >> "\$HOME/steam_error.log"
                                if [ "\${MODIFIER_HELD:-0}" -eq 1 ]; then
                                    MODIFIER_HELD=0
                                    echo "[DEBUG-COMBO] >>> COMBO FIRE <<<" >> "\$HOME/steam_error.log"
                                    /bin/bash "\$SCRIPT_PATH" trigger &
                                else
                                    echo "[DEBUG-COMBO] Trigger IGNORED (modifier not held)" >> "\$HOME/steam_error.log"
                                fi
                            fi
                        else
                            if echo "\$line" | grep -q "code \$TARGET_BTN_CODE.*value 1"; then
                                echo "[DEBUG-SINGLE] Single trigger fired!" >> "\$HOME/steam_error.log"
                                /bin/bash "\$SCRIPT_PATH" trigger &
                            fi
                        fi
                    done
                ) &
                LISTENER_PIDS="\$LISTENER_PIDS \$!"
            fi
        done
        echo "\$LISTENER_PIDS" > /tmp/xbox-steam-pids.txt
        
        while true; do
            sleep 2
            STILL_CONNECTED=1

            for NUM in \$EVENT_NUMS; do
                if [ ! -e "/dev/input/event\$NUM" ]; then
                    STILL_CONNECTED=0
                    break
                fi
            done
            
            if [ \$STILL_CONNECTED -eq 0 ]; then
                echo "⚠️ Device disconnected! Cleaning up background processes..."
                
                for pid in \$LISTENER_PIDS; do
                    kill \$pid 2>/dev/null
                done
                
                echo "  Re-scanning hardware..."
                break
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
if [ "\$1" == "trigger" ]; then
    [ -f /tmp/xbox-steam-calibrating ] && exit 0
    [ -f "\$HOME/steam_error.log" ] && [ \$(stat -c%s "\$HOME/steam_error.log" 2>/dev/null || echo 0) -gt 524288 ] && mv "\$HOME/steam_error.log" "\$HOME/steam_error.log.old"

    exec >> "\$HOME/steam_error.log" 2>&1
    echo "========================================="
    echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
    echo "Timestamp: \$(date)"
    echo "─────────────────────────────────────────"

    export WAYLAND_DISPLAY=\$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
    export DISPLAY=\$(systemctl --user show-environment | grep '^DISPLAY=' | cut -d= -f2)
    export XDG_RUNTIME_DIR="/run/user/\$(id -u)"

    # 2. If systemd lacks the Wayland variable (started too early), find the graphical session manually
    if [ -z "\$WAYLAND_DISPLAY" ]; then
        # Find PID of the active compositor (supports Hyprland, Sway, Wayfire, etc.)
        COMPOSITOR_PID=\$(pgrep -u "\$USER" -x "Hyprland|sway|wayfire|gnome-shell|kwin_wayland" | head -n 1)
        
        if [ -n "\$COMPOSITOR_PID" ]; then
            export WAYLAND_DISPLAY=\$(grep -z '^WAYLAND_DISPLAY=' /proc/\$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export DISPLAY=\$(grep -z '^DISPLAY=' /proc/\$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export HYPRLAND_INSTANCE_SIGNATURE=\$(grep -z '^HYPRLAND_INSTANCE_SIGNATURE=' /proc/\$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
        fi
    fi

    # Double-check that we have a display now, otherwise set standard fallbacks
    [ -z "\$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY="wayland-0"
    [ -z "\$DISPLAY" ] && export DISPLAY=":0"

    CURRENT_ACTIVE_WS=\$(hyprctl monitors | awk '/active workspace:/ {print \$3; exit}')
    TARGET_WORKSPACE=\${CURRENT_ACTIVE_WS:-"1"}
    echo "Current active workspace in focus: \$TARGET_WORKSPACE"

    PID_LIST=\$(pgrep -u "\$USER_NAME" -x "steam")

    if [ -n "\$PID_LIST" ]; then
        echo "Steam is running. Searching for Steam window workspace..."
        
        STEAM_WS=\$(hyprctl clients | awk '
            /^Window/ { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                is_steam = 0
                ws = ""
            }
            /workspace:/ { ws = \$2 }
            /class: [Ss]team/ { is_steam = 1 }
            END { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                print (last_steam_ws != "") ? last_steam_ws : "unknown"
            }
        ')
        
        if [ -n "\$STEAM_WS" ] && [ "\$STEAM_WS" -eq "\$STEAM_WS" ] 2>/dev/null; then
            TARGET_WORKSPACE="\$STEAM_WS"
            echo "Found Steam on Workspace: \$TARGET_WORKSPACE"
        else
            echo "Steam is running but no open window found yet. Staying on current workspace."
        fi
    else
        echo "Steam is not running. It will be launched on the current workspace (\$TARGET_WORKSPACE)."
    fi

    echo "Forcing focus to Hyprland Workspace \$TARGET_WORKSPACE via modern Lua eval..."
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \$TARGET_WORKSPACE }))"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'class:[Ss]team' }))" 2>/dev/null || true
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 2, window = 'class:[Ss]team' }))" 2>/dev/null || true

    if [ -n "\$PID_LIST" ]; then
        echo "Status: Triggering Big Picture..."
        steam steam://open/bigpicture >/dev/null 2>&1 &
    else
        echo "Status: Launching Big Picture from scratch..."
        systemd-run --user --scope --unit=steam-app steam -bigpicture >/dev/null 2>&1 &
    fi
    echo "=== TRIGGER COMPLETE ==="
    echo "========================================="
fi
EOF

chmod +x "$HOME/run_steam.sh"

if systemctl is-enabled xbox-steam.service &>/dev/null || [ -f /etc/systemd/system/xbox-steam.service ]; then
    echo "󰃢  Cleaning up the old global system service..."
    sudo systemctl disable --now xbox-steam.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/xbox-steam.service
    sudo systemctl daemon-reload
fi

echo "  Adding sudoers rule for evtest..."
SU_FILE="/etc/sudoers.d/xbox-steam-evtest"
echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/evtest" | sudo tee "$SU_FILE" > /dev/null
sudo chmod 440 "$SU_FILE"

mkdir -p "$HOME/.config/systemd/user"

log_info "Creating/Updating systemd user service (~/.config/systemd/user/xbox-steam.service)..."
cat << EOF > "$HOME/.config/systemd/user/xbox-steam.service"
[Unit]
Description=Steam Big Picture Trigger
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash $HOME/run_steam.sh listen
ExecStop=/bin/sh -c 'pid_file="/tmp/xbox-steam-pids.txt"; if [ -f "\$pid_file" ]; then xargs kill < "\$pid_file" 2>/dev/null; rm -f "\$pid_file"; fi'
KillMode=process
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

log_info "Reloading systemd configuration..."
if ! run_cmd systemctl --user daemon-reload; then
    log_info "[!] Failed to reload systemd configuration."
fi

log_info "Enabling service for automatic boot..."
systemctl --user disable xbox-steam.service &>/dev/null

if run_cmd systemctl --user enable xbox-steam.service; then
    log_info "Service enabled successfully."
fi

log_info "Ensuring background execution via lingering..."
if run_cmd loginctl enable-linger "$USER_NAME"; then
    log_info "Lingering enabled for $USER_NAME."
fi

log_info "Starting service now..."
if ! run_cmd systemctl --user restart xbox-steam.service; then
    log_info "[!] Failed to start service."
fi

echo "─────────────────────────────────────────"
echo -e "${GREEN}  Inst${DARK_GREEN}alla${DARKEST_GREEN}tion${GREEN}/Up${DARK_GREEN}da${DARKEST_GREEN}te${GREEN} com${DARK_GREEN}ple${DARKEST_GREEN}te!${CLEAR}"
echo "   Your device is mapped dynamically."
echo "   If it doesn't work, check the log: cat ~/steam_error.log"
