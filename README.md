# Hyprland Steam Shortcut (Xbox/Guide Button Fix)

A guide and script to map the Xbox/Guide (Home/Mode) button on your controller (e.g., Flydigi, Xbox controllers) to launch **Steam Big Picture** globally in a modern Hyprland/Wayland session.

---

## 1. Prerequisites & Installation

To capture controller inputs globally (even when no window is focused) and bypass Wayland's strict security layers, we need an input testing utility and a background system service.
Install the following package using your package manager (e.g., `pacman` on Arch Linux):

```bash
# 1. xpad - Standard Xbox controller driver (usually built into the kernel, make sure it's not blacklisted)
# 2. evtest - Utility to monitor input events and find button names

sudo pacman -S evtest
```
### ⚠️ Crucial: Ensure the xpad Driver is Loaded

Sometimes the standard Xbox controller driver (xpad) is not loaded automatically by the kernel, making the controller completely invisible to evtest.

1. Force load the driver immediately:
```bash
sudo modprobe xpad
```

2. Ensure the driver loads automatically on boot:
```bash
echo "xpad" | sudo tee /etc/modules-load.d/xpad.conf
```

## 2. Identify the Button Name using evtest

Before writing the configuration, we must find out exactly what the system calls your Xbox/Mode button.

1. Run evtest as root:
```bash
sudo evtest
```
2. You will see a list of all available input devices. Locate your controller (e.g., Microsoft X-Box 360 pad or Flydigi), type its corresponding number, and press Enter.
3. Press the Xbox/Guide button on your controller.
4. Look at the terminal output. Search for (EV_KEY) and the name inside the parentheses. For example:

```Plaintext
Event: time 1717968600.123456, type 1 (EV_KEY), code 316 (BTN_MODE), value 1
```

## 3. Create the Systemd Service

Instead of using a desktop-level hotkey daemon (which Wayland often blocks), we create a lightweight systemd service that monitors the controller directly at the kernel layer using evtest.

1. Create or open the file:
```bash
sudo nano /etc/systemd/system/xbox-steam.service
```
2. Paste the following configuration:
```Ini, TOML
[Unit]
Description=Xbox Steam Big Picture Trigger
After=systemd-udevd.service

[Service]
Type=simple
# NOTE: Users should replace 'YOUR_USERNAME' with their actual username
ExecStart=/bin/bash /home/YOUR_USERNAME/run_steam.sh listen
Restart=always
RestartSec=5

# Force systemd to kill BOTH the wrapper script and evtest simultaneously on restart
KillMode=control-group
SendSIGKILL=yes

[Install]
WantedBy=basic.target
```
(Make sure to replace YOUR_USERNAME with your actual Linux username!)

3. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

## 4. Create the Automation Script (run_steam.sh)

This script does two things:
1. When started by systemd, it dynamically finds the correct input event for the controller and listens for the button press.
2. When the button is pressed, it safely bridges the command into your active graphical session (Wayland/Hyprland) with correct display variables.

Create the script in your home directory:
```bash
nano ~/run_steam.sh
```

⚠️ Paste the following code and remember to change the variables ⚠️

```bash
#!/bin/bash

# === CONFIGURATION ===
# Replace these with your actual username, UID, and display variables
# (Run 'id' in terminal if you are unsure about your USER_NAME or USER_ID)
USER_NAME="YOUR_USERNAME"
USER_ID="1000"

# NOTE: Run 'echo $DISPLAY' and 'echo $WAYLAND_DISPLAY' in your terminal 
# to verify if your session uses :0/wayland-0 or :1/wayland-1
DISPLAY_VAR=":1"
WAYLAND_VAR="wayland-1"
# =====================

# Automatically detect the script's own path dynamically so the user 
# doesn't have to hardcode /home/username/run_steam.sh inside the loops.
SCRIPT_PATH="$(realpath "$0")"

# If started with "listen", act as the background listener
if [ "$1" == "listen" ]; then
    echo "Starting listener..."

    # Loop until the controller is actually found in the system
    while true; do
        EVENT_NUMS=$(awk '/Name="Microsoft X-Box 360 pad"/{cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if($i~/event/) pr>

        if [ -n "$EVENT_NUMS" ]; then
            break
        fi
        echo "No controller found yet. Retrying in 3 seconds..."
        sleep 3
    done

    # Start a parallel background listener for each matching event node
    for NUM in $EVENT_NUMS; do
        echo "Listening on /dev/input/event$NUM"
        evtest /dev/input/event$NUM 2>/dev/null | while read -r line; do
            if echo "$line" | grep -q 'code 316 (BTN_MODE), value 1'; then
                /bin/bash "$SCRIPT_PATH" trigger &
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
exec >> "/home/$USER_NAME/steam_error.log" 2>&1

echo "========================================="
echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
echo "Timestamp: $(date)"
echo "-----------------------------------------"

# Check for existing Steam processes
PID_LIST=$(pgrep -u "$USER_NAME" -x "steam")

if [ -n "$PID_LIST" ]; then
    echo "Status: Steam is already running! Sending command to open Big Picture Mode..."
    sudo -u "$USER_NAME" env DISPLAY="$DISPLAY_VAR" WAYLAND_DISPLAY="$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/$USER_ID" s>
else
    echo "Status: Steam is not running. Launching Big Picture Mode from scratch..."
    sudo -u "$USER_NAME" env DISPLAY="$DISPLAY_VAR" WAYLAND_DISPLAY="$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/$USER_ID" s>
fi

echo "=== TRIGGER COMPLETE ==="
echo "========================================="
```
3. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

## 5. Permissions & Activation

Make the script executable, reload systemd configurations, and enable the service:

```bash
# Make the script executable (adjust path if needed)
chmod +x ~/run_steam.sh

# Enable and start the new systemd service
sudo systemctl daemon-reload
sudo systemctl enable --now xbox-steam.service
```

## Troubleshooting

If Steam doesn't open when you press the button, check the generated log file to see what went wrong:
```bash
cat ~/steam_error.log
```

To check if the service successfully located your controller and is actively running, use:
```bash
sudo systemctl status xbox-steam.service
```
(Press the Xbox button and verify it matches BTN_MODE and successfully executes the bash command).
