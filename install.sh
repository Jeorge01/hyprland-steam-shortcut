#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "========================================="
echo "  Hyprland Steam Shortcut Install script"
echo "========================================="

# -------------------------------------------------------------------------
# STEP 1: PRE-FLIGHT CHECKS (FAIL-FAST)
# -------------------------------------------------------------------------

# Ensure the script is NOT run as root directly (we need the correct $HOME)
if [ "$(id -u)" = "0" ]; then
    echo "⚠️ Do not run this script with 'sudo' or as root directly."
    echo "Run it as a regular user. The script will ask for sudo when needed."
    exit 1
fi

# Verify pacman is available (ensuring an Arch-based system)
if ! command -v pacman &> /dev/null; then
    echo "❌ This script is designed for Arch Linux (uses pacman)."
    echo "Your distribution is currently not supported automatically."
    exit 1
fi

# -------------------------------------------------------------------------
# STEP 2: DEPENDENCIES & DRIVERS
# -------------------------------------------------------------------------

# Quick check if evtest is already installed
if command -v evtest &> /dev/null; then
    echo "📦 evtest is already installed, skipping..."
else
    echo "📦 evtest is missing. Installing via pacman..."
    sudo pacman -S --needed --noconfirm evtest
fi

echo "⚙️ Configuring xpad driver..."
# Check if xpad.conf is already created to avoid overwriting it unnecessarily
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

# Get display variables (fallback to defaults if empty)
DISPLAY_VAR=${DISPLAY:-":0"}
WAYLAND_VAR=${WAYLAND_DISPLAY:-"wayland-0"}

echo "Detected values:"
echo " - User:    $USER_NAME (UID: $USER_ID)"
echo " - Display: $DISPLAY_VAR"
echo " - Wayland: $WAYLAND_VAR"
echo "-----------------------------------------"

# -------------------------------------------------------------------------
# STEP 4: CREATE FILES & ACTIVATE (Idempotent / Safe to re-run)
# -------------------------------------------------------------------------

# Stop the service first if it's already running, so we can safely overwrite files
if systemctl is-active --quiet xbox-steam.service; then
    echo "🔄 Existing service detected. Stopping it safely for update..."
    sudo systemctl stop xbox-steam.service
fi

echo "📝 Creating/Updating automation script (~/run_steam.sh)..."
cat << EOF > "$HOME/run_steam.sh"
#!/bin/bash

# === CONFIGURATION (Auto-generated) ===
USER_NAME="$USER_NAME"
USER_ID="$USER_ID"
DISPLAY_VAR="$DISPLAY_VAR"
WAYLAND_VAR="$WAYLAND_VAR"
# =====================================

SCRIPT_PATH="\$(realpath "\$0")"

if [ "\$1" == "listen" ]; then
    echo "Starting listener..."

    while true; do
        EVENT_NUMS=\$(awk '/Name="Microsoft X-Box 360 pad"/{cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if(\$i~/event/) print \$i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+')

        if [ -n "\$EVENT_NUMS" ]; then
            break
        fi
        echo "No controller found yet. Retrying in 3 seconds..."
        sleep 3
    done

    for NUM in \$EVENT_NUMS; do
        echo "Listening on /dev/input/event\$NUM"
        evtest /dev/input/event\$NUM 2>/dev/null | while read -r line; do
            if echo "\$line" | grep -q 'code 316 (BTN_MODE), value 1'; then
                /bin/bash "\$SCRIPT_PATH" trigger &
            fi
        done
    done

    while true; do
        sleep 60
    done
fi

# --- TRIGGER EXECUTION ---
exec >> "/home/\$USER_NAME/steam_error.log" 2>&1
echo "========================================="
echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
echo "Timestamp: \$(date)"
echo "-----------------------------------------"

PID_LIST=\$(pgrep -u "\$USER_NAME" -x "steam")

if [ -n "\$PID_LIST" ]; then
    echo "Status: Steam is already running! Sending command to open Big Picture Mode..."
    sudo -u "\$USER_NAME" env DISPLAY="\$DISPLAY_VAR" WAYLAND_DISPLAY="\$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/\$USER_ID" nohup steam steam://open/bigpicture >/dev/null 2>&1 &
else
    echo "Status: Steam is not running. Launching Big Picture Mode from scratch..."
    sudo -u "\$USER_NAME" env DISPLAY="\$DISPLAY_VAR" WAYLAND_DISPLAY="\$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/\$USER_ID" nohup steam -bigpicture >/dev/null 2>&1 &
fi
echo "=== TRIGGER COMPLETE ==="
echo "========================================="
EOF

chmod +x "$HOME/run_steam.sh"

echo "⚙️ Creating/Updating systemd service (/etc/systemd/system/xbox-steam.service)..."
sudo cat << EOF > /etc/systemd/system/xbox-steam.service
[Unit]
Description=Xbox Steam Big Picture Trigger
After=systemd-udevd.service

[Service]
Type=simple
ExecStart=/bin/bash /home/$USER_NAME/run_steam.sh listen
Restart=always
RestartSec=5
KillMode=control-group
SendSIGKILL=yes

[Install]
WantedBy=basic.target
EOF

echo "🔄 Reloading systemd and restarting service..."
sudo systemctl daemon-reload
sudo systemctl unmask xbox-steam.service
sudo systemctl reenable --now xbox-steam.service

echo "-----------------------------------------"
echo "✅ Installation/Update complete!"
echo "Try pressing the Xbox/Guide button on your controller."
echo "If it doesn't work, check the log: cat ~/steam_error.log"
echo "========================================="
