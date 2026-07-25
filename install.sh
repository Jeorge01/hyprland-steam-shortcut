#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

HYPR_BLUE="\033[38;2;94;204;227m"
HYPR_DARK_BLUE="\033[38;2;85;184;204m"
HYPR_DARKEST_BLUE="\033[38;2;72;162;180m"

GREEN="\033[38;2;94;227;149m"
DARK_GREEN="\033[38;2;85;204;134m"
DARKEST_GREEN="\033[38;2;72;180;117m"

YELLOW='\033[38;2;244;208;63m'
RED='\033[38;2;231;76;60m'
BLUE='\033[38;2;52;152;219m'
CYAN='\033[38;2;26;188;156m'
WHITE='\033[1;37m'
CLEAR='\033[0m'

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
echo -e ""

sudo -v || exit 1
while true; do sudo -n true; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!

cleanup() {
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

# Detect Package Manager
if command -v pacman &> /dev/null; then
    DISTRO="󰣇 Arch"
    PKG_MANAGER="pacman"
elif command -v dnf &> /dev/null; then
    DISTRO=" Fedora"
    PKG_MANAGER="dnf"
else
    echo -e "${RED}❌ Unsupported distribution.${CLEAR}"
    echo -e "${RED}   This script currently only supports Arch Linux (pacman) and Fedora (dnf).${CLEAR}"
    exit 1
fi

if ! command -v steam &> /dev/null; then
    echo -e "${RED}❌ ERROR: Steam is missing from your system.${CLEAR}"
    echo -e "${RED}   Please install Steam first before running this installation script.${CLEAR}"
    exit 1
fi

USER_NAME=$(id -un)
USER_ID=$(id -u)

echo -e "󰌽  Detected OS environment: ${HYPR_BLUE}${DISTRO}${CLEAR} (using ${PKG_MANAGER})"

# -------------------------------------------------------------------------
# STEP 2: DEPENDENCIES & DRIVERS
# -------------------------------------------------------------------------

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
        sudo modprobe xpad || true
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
# LIVE BUTTON & DEVICE DETECTION (60s timeout & graceful abort)
# -------------------------------------------------------------------------
echo ""
echo -e "${HYPR_BLUE}  IN${HYPR_DARK_BLUE}PU${HYPR_DARKEST_BLUE}T${HYPR_BLUE} DE${HYPR_DARK_BLUE}VI${HYPR_DARKEST_BLUE}CE${HYPR_BLUE} CALI${HYPR_DARK_BLUE}BRAT${HYPR_DARKEST_BLUE}ION${HYPR_BLUE} RE${HYPR_DARK_BLUE}AD${HYPR_DARKEST_BLUE}Y${CLEAR}"
echo -e "   Before we begin, make sure your input device is turned ${GREEN}ON${CLEAR} and connected."
echo -e "   Once you press ENTER, you will have ${YELLOW}60 seconds${CLEAR} to press the target button."
echo ""
echo -e -n "  Press ${HYPR_BLUE}[ENTER]${CLEAR} when you are ready to calibrate (or ${RED}Ctrl+C${CLEAR} to abort)..."
read -r </dev/tty
echo ""

# Create a temporary file to store output from background workers
TMP_CAPTURE=$(mktemp)

# Start a listener on EVERY event device simultaneously in the background
set +e
for ev in /dev/input/event*; do
    if [ -r "$ev" ] || [ "$(id -u)" = "0" ] || command -v sudo &>/dev/null; then
        # Background listeners will run for max 65 seconds if not killed sooner
        sudo timeout 65 evtest "$ev" 2>/dev/null | grep --line-buffered -m 1 "code.*BTN_.*value 1" | sed "s|^|$ev: |" >> "$TMP_CAPTURE" &
    fi
done

# Active polling loop: Check every 0.25 seconds if something was written to the file
CAPTURED_LINE=""
for ((i=0; i<240; i++)); do  # 240 * 0.25s = 60 seconds maximum wait
    if [ -s "$TMP_CAPTURE" ]; then
        CAPTURED_LINE=$(head -n 1 "$TMP_CAPTURE")
        break
    fi
    
    # Print a dot every second (every 4th loop iteration) to show activity
    if (( i % 4 == 0 )); then
        echo -n ". "
    fi
    
    sleep 0.25
done

# Instantly kill all background listeners as soon as we break or timeout
[[ -n "$(jobs -p)" ]] && kill $(jobs -p) 2>/dev/null || true
set -e

# Clear the trailing dots line
echo ""

rm -f "$TMP_CAPTURE"

if [ -z "$CAPTURED_LINE" ]; then
    echo ""
    echo -e "${RED}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"
    echo -e "${RED}│${CLEAR} ❌ ERROR: No input device activity detected within 60s.         ${RED}│${CLEAR}"
    echo -e "${RED}│${CLEAR}    Installation aborted. Please try again.                      ${RED}│${CLEAR}"
    echo -e "${RED}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
    echo -e ""
    echo -e "   ${YELLOW}Checking for conflicting processes...${CLEAR}"
    echo -e ""

    # Check known conflicting services
    CONFLICT_FOUND=0
    if systemctl is-active --quiet input-remapper 2>/dev/null; then
        echo -e "   ${RED}●${CLEAR} input-remapper is running — ${YELLOW}sudo systemctl stop input-remapper${CLEAR}"
        CONFLICT_FOUND=1
    fi
    if pgrep -x "hkdm" > /dev/null 2>&1; then
        echo -e "   ${RED}●${CLEAR} hkdm is running — ${YELLOW}sudo pacman -R hkdm${CLEAR}"
        CONFLICT_FOUND=1
    fi

    # Check who actually holds the input devices
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
else
    # Parse out the event path, button code, and name
    DETECTED_EV=$(echo "$CAPTURED_LINE" | awk -F':' '{print $1}')
    TARGET_BTN_CODE=$(echo "$CAPTURED_LINE" | grep -oP 'code \K[0-9]+')
    TARGET_BTN_NAME=$(echo "$CAPTURED_LINE" | grep -oP 'BTN_[A-Z0-9]+')
    TARGET_DEV_NAME=$(awk -v RS='' '/Handlers=.*'"${DETECTED_EV##*/}"'( |$)/' /proc/bus/input/devices | grep -oP 'Name="\K[^"]+')
    
    if [ -z "$TARGET_DEV_NAME" ]; then
        TARGET_DEV_NAME="Generic Controller"
    fi

    RAW_L1="  Button press detected!"
    RAW_L2="  Detected Device: $TARGET_DEV_NAME"
    RAW_L3=" 󰪥 Mapped Button:   $TARGET_BTN_NAME (Code: $TARGET_BTN_CODE)"

    PAD_L1=$(echo "$RAW_L1" | awk '{printf "%s%*s", $0, 62-length($0), ""}')
    PAD_L2=$(echo "$RAW_L2" | awk '{printf "%s%*s", $0, 62-length($0), ""}')
    PAD_L3=$(echo "$RAW_L3" | awk '{printf "%s%*s", $0, 62-length($0), ""}')

    COLOR_L1="${HYPR_BLUE}   Bu${HYPR_DARK_BLUE}tt${HYPR_DARKEST_BLUE}on${HYPR_BLUE} pr${HYPR_DARK_BLUE}es${HYPR_DARKEST_BLUE}s${HYPR_BLUE} det${HYPR_DARK_BLUE}ect${HYPR_DARKEST_BLUE}ed!${CLEAR}${PAD_L1#*detected!}"
    COLOR_L2="${HYPR_BLUE}   Det${HYPR_DARK_BLUE}ect${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} De${HYPR_DARK_BLUE}vi${HYPR_DARKEST_BLUE}ce${HYPR_BLUE}: ${CLEAR}${WHITE}${TARGET_DEV_NAME}${CLEAR}${PAD_L2#*Device: $TARGET_DEV_NAME}"
    COLOR_L3="${HYPR_BLUE} 󰪥  Ma${HYPR_DARK_BLUE}pp${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} Bu${HYPR_DARK_BLUE}tt${HYPR_DARKEST_BLUE}on${HYPR_BLUE}:   ${CLEAR}${WHITE}${TARGET_BTN_NAME} (Code: ${TARGET_BTN_CODE})${CLEAR}${PAD_L3#*Button:   $TARGET_BTN_NAME (Code: $TARGET_BTN_CODE)}"

    echo ""
    echo -e "${HYPR_BLUE}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"
    echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L1}${HYPR_BLUE}  │${CLEAR}"
    echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L2}${HYPR_BLUE}  │${CLEAR}"
    echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L3}${HYPR_BLUE}  │${CLEAR}"
    echo -e "${HYPR_BLUE}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
fi
echo "─────────────────────────────────────────"

## -------------------------------------------------------------------------
# STEP 3: CREATE FILES & ACTIVATE
# -------------------------------------------------------------------------

if systemctl --user is-active --quiet xbox-steam.service; then
    echo "  Existing service detected. Stopping safely..."
    
    # 1. Döda våra specifika processer FÖRST (innan systemd hinner radera filen)
    if [ -f /tmp/xbox-steam-pids.txt ]; then
        log_info "Killing existing listeners..."
        xargs kill -9 < /tmp/xbox-steam-pids.txt 2>/dev/null || true
        rm -f /tmp/xbox-steam-pids.txt
    fi
    
    # 2. Stoppa tjänsten efteråt
    systemctl --user stop xbox-steam.service &>/dev/null
fi

# 3. Säkerhetsåtgärd: Döda eventuella kvarvarande evtest som matchar vår sökning
# Detta fångar "spök-bindningar" även om de tappat kontakten med PID-filen
sudo pkill -9 -f "[e]vtest" 2>/dev/null || true

log_info "Creating/Updating automation script (~/run_steam.sh)..."
cat << EOF > "$HOME/run_steam.sh"
#!/bin/bash

# === CONFIGURATION (Auto-generated via Calibration) ===
USER_NAME="$USER_NAME"
USER_ID="$USER_ID"
TARGET_DEV_NAME="$TARGET_DEV_NAME"
TARGET_BTN_CODE="$TARGET_BTN_CODE"
TARGET_BTN_NAME="$TARGET_BTN_NAME"
# ======================================================

SCRIPT_PATH="\$(realpath "\$0")"

if [ "\$1" == "listen" ]; then
    echo "Starting listener..."

    while true; do
        while true; do
            CHECK_NUMS=\$(awk -v name="\$TARGET_DEV_NAME" '
                BEGIN { RS="\n\n|--\n"; IGNORECASE=1 }
                \$0 ~ "N: Name=\"" name "\"" && \$0 ~ "P: Phys=.+" {
                    if (match(\$0, /Handlers=[^\n]+/)) {
                        handlers = substr(\$0, RSTART, RLENGTH);
                        split(handlers, arr, " ");
                        for (i in arr) {
                            if (arr[i] ~ /event/) {
                                gsub(/[^0-9]/, "", arr[i]);
                                print arr[i];
                            }
                        }
                    }
                }
            ' /proc/bus/input/devices)

            if [ -n "\$CHECK_NUMS" ]; then
                EVENT_NUMS="\$CHECK_NUMS"
                break
            fi

            echo "Waiting for your specific physical controller (\$TARGET_DEV_NAME) to initialize..."
            sleep 2
        done
        
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
                        if echo "\$line" | grep -q "code \$TARGET_BTN_CODE (\$TARGET_BTN_NAME), value 1"; then
                            /bin/bash "\$SCRIPT_PATH" trigger &
                        fi
                    done
                ) &
                LISTENER_PIDS="\$LISTENER_PIDS \$!"
                echo "\$LISTENER_PIDS" > /tmp/xbox-steam-pids.txt
            fi
        done

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
    LOCKFILE="/tmp/steam-trigger.lock"
    exec 200>"\$LOCKFILE"
    flock -n 200 || { echo "Trigger already running, skipping."; exit 0; }

    [ -f "\$HOME/steam_error.log" ] && [ \$(stat -c%s "\$HOME/steam_error.log" 2>/dev/null || echo 0) -gt 524288 ] && mv "\$HOME/steam_error.log" "\$HOME/steam_error.log.old"

    exec >> "\$HOME/steam_error.log" 2>&1
    echo "========================================="
    echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
    echo "Timestamp: \$(date)"
    echo "─────────────────────────────────────────"

    export WAYLAND_DISPLAY=\$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
    export DISPLAY=\$(systemctl --user show-environment | grep '^DISPLAY=' | cut -d= -f2)
    export XDG_RUNTIME_DIR="/run/user/\$(id -u)"

    # 2. Om systemd saknar Wayland-variabeln (dvs. startade för tidigt), leta upp den grafiska sessionen manuellt
    if [ -z "\$WAYLAND_DISPLAY" ]; then
        # Hitta PID för det aktiva gränssnittet (stöder Hyprland, Sway, Wayfire etc.)
        COMPOSITOR_PID=\$(pgrep -u "\$USER" -x "Hyprland|sway|wayfire|gnome-shell|kwin_wayland" | head -n 1)
        
        if [ -n "\$COMPOSITOR_PID" ]; then
            export WAYLAND_DISPLAY=\$(grep -z '^WAYLAND_DISPLAY=' /proc/\$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export DISPLAY=\$(grep -z '^DISPLAY=' /proc/\$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export HYPRLAND_INSTANCE_SIGNATURE=\$(grep -z '^HYPRLAND_INSTANCE_SIGNATURE=' /proc/\$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
        fi
    fi

    # Dubbelkolla att vi faktiskt har en display nu, annars sätter vi standard-fallbacks
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
echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/evtest" | sudo tee "$SU_FILE" > /dev/null
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
ExecStop=/bin/sh -c 'pid_file="/tmp/xbox-steam-pids.txt"; if [ -f "\$pid_file" ]; then xargs kill -9 < "\$pid_file" 2>/dev/null; rm -f "\$pid_file"; fi'
KillMode=process
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

log_info "Reloading systemd configuration..."
run_cmd systemctl --user daemon-reload

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
