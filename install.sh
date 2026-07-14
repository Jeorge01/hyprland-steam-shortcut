#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

GREEN='\033[38;2;40;180;99m'
YELLOW='\033[38;2;244;208;63m'
RED='\033[38;2;231;76;60m'
BLUE='\033[38;2;52;152;219m'
CYAN='\033[38;2;26;188;156m'
CLEAR='\033[0m'

echo -e ""
echo -e "${GREEN}=========================================${CLEAR}"
echo -e "${GREEN}  Hyprland Steam Shortcut Install script${CLEAR}"
echo -e "${GREEN}=========================================${CLEAR}"
echo -e ""

sudo -v || exit 1
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

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
    DISTRO="Arch"
    PKG_MANAGER="pacman"
elif command -v dnf &> /dev/null; then
    DISTRO="Fedora"
    PKG_MANAGER="dnf"
else
    echo -e "${RED}❌ Unsupported distribution.${CLEAR}"
    echo -e "${RED}   This script currently only supports Arch Linux (pacman) and Fedora (dnf).${CLEAR}"
    exit 1
fi

echo -e "💻 Detected OS environment: ${CYAN}${DISTRO}${CLEAR} (using ${PKG_MANAGER})"

# -------------------------------------------------------------------------
# STEP 2: DEPENDENCIES & DRIVERS
# -------------------------------------------------------------------------

if command -v evtest &> /dev/null; then
    echo "📦 evtest is already installed, skipping..."
else
    echo "📦 evtest is missing. Installing via $PKG_MANAGER..."
    if [ "$PKG_MANAGER" = "pacman" ]; then
        sudo pacman -S --needed --noconfirm evtest
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        sudo dnf install -y evtest
    fi
fi

echo "⚙️ Configuring xpad driver..."
if [ -f "/etc/modules-load.d/xpad.conf" ]; then
    echo "⚙️ xpad is already configured for auto-load, skipping..."
else
    if ! lsmod | grep -q "xpad"; then
        echo "Loading xpad into the kernel..."
        sudo modprobe xpad || true
    fi
    echo "Setting xpad to load automatically on boot..."
    echo "xpad" | sudo tee /etc/modules-load.d/xpad.conf > /dev/null
fi

# -------------------------------------------------------------------------
# STEP 3: ENVIRONMENT VARIABLES
# -------------------------------------------------------------------------
echo "-----------------------------------------"
echo "🔍 Detecting system variables..."

USER_NAME=$(whoami)
USER_ID=$(id -u)
DISPLAY_VAR=${DISPLAY:-":0"}
WAYLAND_VAR=${WAYLAND_DISPLAY:-"wayland-0"}

echo "    Detected values:"
echo "     - User:    $USER_NAME (UID: $USER_ID)"
echo "     - Display: $DISPLAY_VAR"
echo "     - Wayland: $WAYLAND_VAR"
echo "-----------------------------------------"

# -------------------------------------------------------------------------
# LIVE BUTTON & CONTROLLER DETECTION (60s timeout & graceful abort)
# -------------------------------------------------------------------------
echo -e "${BLUE}🎮 CONTROLLER CALIBRATION READY${CLEAR}"
echo -e "    Before we begin, make sure your controller is turned ${GREEN}ON${CLEAR} and connected."
echo -e "    Once you press ENTER, you will have ${YELLOW}60 seconds${CLEAR} to press the target button."
echo ""
echo -e -n "👉 Press ${GREEN}[ENTER]${CLEAR} when you are ready to calibrate (or ${RED}Ctrl+C${CLEAR} to abort)..."
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
    echo "-----------------------------------------"
    echo -e "${RED}❌ ERROR: No controller input detected within 60 seconds.${CLEAR}"
    echo -e "${RED}   Installation aborted. Please ensure your controller is active and try again.${CLEAR}"
    echo "-----------------------------------------"
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

    echo ""
    echo -e "-----------------------------------------"
    echo -e "    ${GREEN}Button press detected!${CLEAR}"
    echo -e "    ${GREEN}Detected Device:${CLEAR} ${TARGET_DEV_NAME}"
    echo -e "    ${GREEN}Mapped Button:${CLEAR}   ${TARGET_BTN_NAME} (Code: ${TARGET_BTN_CODE})"
fi
echo "-----------------------------------------"

## -------------------------------------------------------------------------
# STEP 4: CREATE FILES & ACTIVATE
# -------------------------------------------------------------------------

if systemctl is-active --quiet xbox-steam.service; then
    echo "🔄 Existing service detected. Stopping safely before update..."
    sudo systemctl stop xbox-steam.service
    sudo pkill -f evtest || true
fi

echo "   Creating/Updating automation script (~/run_steam.sh)..."
cat << EOF > /home/$USER_NAME/run_steam.sh
#!/bin/bash

# === CONFIGURATION (Auto-generated via Calibration) ===
USER_NAME="$USER_NAME"
USER_ID="$USER_ID"
DISPLAY_VAR="$DISPLAY_VAR"
WAYLAND_VAR="$WAYLAND_VAR"
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

        echo "Your calibrated controller is ready! Initializing listener..."

        LISTENER_PIDS=""

        for NUM in \$EVENT_NUMS; do
            if [ -e "/dev/input/event\$NUM" ]; then
                echo "Listening on /dev/input/event\$NUM"
                (
                    evtest /dev/input/event\$NUM 2>/dev/null | while read -r line; do
                        if echo "\$line" | grep -q "code \$TARGET_BTN_CODE (\$TARGET_BTN_NAME), value 1"; then
                            /bin/bash "\$SCRIPT_PATH" trigger &
                        fi
                    done
                ) &
                LISTENER_PIDS="\$LISTENER_PIDS \$!"
            fi
        done

        while [ -n "\$LISTENER_PIDS" ]; do
            sleep 10
            ANY_ALIVE=0
            for pid in \$LISTENER_PIDS; do
                if kill -0 \$pid 2>/dev/null; then
                    ANY_ALIVE=1
                fi
            done
            
            if [ \$ANY_ALIVE -eq 0 ]; then
                echo "⚠️ Controller disconnected. Re-scanning hardware..."
                break
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
if [ "\$1" == "trigger" ]; then
    exec >> "/home/\$USER_NAME/steam_error.log" 2>&1
    echo "========================================="
    echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
    echo "Timestamp: \$(date)"
    echo "-----------------------------------------"

    HYPR_SIGNATURE=\$(pgrep -u "\$USER_NAME" -x Hyprland -a | grep -o 'HYPRLAND_INSTANCE_SIGNATURE=[^ ]*' | cut -d= -f2- | head -n1)
    if [ -z "\$HYPR_SIGNATURE" ]; then
        HYPR_SIGNATURE=\$(ls -dt /run/user/\$USER_ID/hypr/* 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
    fi

    CURRENT_ACTIVE_WS=\$(runuser -u "\$USER_NAME" -- env HYPRLAND_INSTANCE_SIGNATURE="\$HYPR_SIGNATURE" XDG_RUNTIME_DIR="/run/user/\$USER_ID" hyprctl monitors | awk '/active workspace:/ {print \$3; exit}')
    
    TARGET_WORKSPACE=\${CURRENT_ACTIVE_WS:-"1"}
    echo "Current active workspace in focus: \$TARGET_WORKSPACE"

    PID_LIST=\$(pgrep -u "\$USER_NAME" -x "steam")

    if [ -n "\$PID_LIST" ]; then
        echo "Steam is running. Searching for Steam window workspace..."
        
        STEAM_WS=\$(runuser -u "\$USER_NAME" -- env HYPRLAND_INSTANCE_SIGNATURE="\$HYPR_SIGNATURE" XDG_RUNTIME_DIR="/run/user/\$USER_ID" hyprctl clients | awk '
            /^Window/ { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                is_steam = 0
                ws = ""
            }
            /class: [Ss]team/ || /initialClass: [Ss]team/ { 
                is_steam = 1 
            }
            /workspace: / {
                line = \$0
                gsub(/[^0-9]/, " ", line)
                split(line, numbers, " ")
                
                for (i = 1; i <= length(numbers); i++) {
                    if (numbers[i] != "") {
                        ws = numbers[i]
                    }
                }
            }
            END { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                print last_steam_ws 
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

    echo "Forcing focus to Hyprland Workspace \$TARGET_WORKSPACE via hyprctl eval..."
    HYPR_ERR=\$(runuser -u "\$USER_NAME" -- env HYPRLAND_INSTANCE_SIGNATURE="\$HYPR_SIGNATURE" XDG_RUNTIME_DIR="/run/user/\$USER_ID" hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \$TARGET_WORKSPACE }))" 2>&1)
    echo "Hyprctl eval output: \${HYPR_ERR:-"Success"}"

    if [ -n "\$PID_LIST" ]; then
        echo "Status: Triggering Big Picture..."
        systemd-run --user --machine="\$USER_NAME@.host" --collect env DISPLAY="\$DISPLAY_VAR" WAYLAND_DISPLAY="\$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/\$USER_ID" dbus-run-session xdg-open "steam://open/bigpicture" >/dev/null 2>&1
    else
        echo "Status: Launching Big Picture from scratch..."
        systemd-run --user --machine="\$USER_NAME@.host" --collect env DISPLAY="\$DISPLAY_VAR" WAYLAND_DISPLAY="\$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/\$USER_ID" steam -bigpicture >/dev/null 2>&1
    fi
    echo "=== TRIGGER COMPLETE ==="
    echo "========================================="
fi
EOF

chmod +x "$HOME/run_steam.sh"

echo "   Creating/Updating systemd service (/etc/systemd/system/xbox-steam.service)..."
cat << EOF | sudo tee /etc/systemd/system/xbox-steam.service > /dev/null
[Unit]
Description=Steam Big Picture Trigger
After=systemd-udevd.service

[Service]
Type=simple
ExecStart=/bin/bash /home/$USER_NAME/run_steam.sh listen
Restart=always
RestartSec=3

[Install]
WantedBy=basic.target
EOF

echo "   Reloading systemd and restarting service..."
sudo systemctl daemon-reload
sudo systemctl unmask xbox-steam.service
sudo systemctl enable xbox-steam.service
sudo systemctl restart xbox-steam.service

echo "-----------------------------------------"
echo -e "${GREEN}✅ Installation/Update complete!${CLEAR}"
echo "   Your controller is mapped dynamically."
echo "   If it doesn't work, check the log: cat ~/steam_error.log"

# -------------------------------------------------------------------------
# FEDORA SPECIFIC NOTE (SELinux warnings)
# -------------------------------------------------------------------------
if [ "$DISTRO" = "Fedora" ]; then
    echo -e ""
    echo -e "${YELLOW}⚠️  Fedora / SELinux Notice:${CLEAR}"
    echo -e "   Since you are running Fedora, SELinux is active by default."
    echo -e "   The systemd service runs as 'root' but spawns a process in your user session."
    echo -e "   If the shortcut does not trigger Steam, check if SELinux blocked it:"
    echo -e "   Run 'sudo setenforce 0' to temporarily disable SELinux. If that fixes it,"
    echo -e "   consider running the service as a systemd --user service instead."
fi

echo "========================================="