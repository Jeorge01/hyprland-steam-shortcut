# Hyprland Steam Shortcut (Xbox/Guide Button Fix)

Automated background service to map the Xbox/Guide button on your controller (Xbox, Flydigi, etc.) to launch Steam Big Picture Mode globally in a Hyprland/Wayland session.

---

## Installation

You can install or update the shortcut trigger automatically using the following command.

### One-line Installer (Recommended)
Open your terminal and run:

```bash
curl -sL https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main/install.sh | bash
```
You could also clone or download the install.sh file and run it like this

```bash
# Clone the repository
git clone https://github.com/Jeorge01/hyprland-steam-shortcut.git
cd hyprland-steam-shortcut

# Make the installer executable and run it
chmod +x install.sh
./install.sh
```
---

## Manual Installation (Alternative)

### 1. Prerequisites & Installation

To capture controller inputs globally (even when no window is focused) and bypass Wayland's strict security layers, we need an input testing utility and a background system service.
Install the following package using your package manager (e.g., `pacman` on Arch Linux):

```bash
# 1. xpad - Standard Xbox controller driver (usually built into the kernel, make sure it's not blacklisted)
# 2. evtest - Utility to monitor input events and find button names

sudo pacman -S evtest
```
### ⚠️ Crucial: Ensure the xpad Driver is Loaded

Sometimes the standard Xbox controller driver (xpad) is not loaded automatically by the kernel, making the controller completely invisible to evtest.

#### 1. Check if it's loaded
Run the following command to see if the driver is currently running in the background:
```bash
lsmod | grep xpad
```

#### 2. Force load the driver immediately
If it wasn't running, you can manually force the kernel to load it right now by running:
```bash
sudo modprobe xpad
```
If this command returns no output, it means the driver is not currently active.

#### 3. Ensure the driver loads automatically on boot:
To prevent having to do this manually every time you restart your system, create a configuration file that tells Arch to always load xpad at startup:
```bash
echo "xpad" | sudo tee /etc/modules-load.d/xpad.conf
```

### 2. Identify the Button Name using evtest

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
⚠️ Save this somewhere since we are using these values as variables later... ⚠️

### 3. Create the Systemd Service

Instead of using a desktop-level hotkey daemon (which Wayland often blocks), we create a lightweight systemd service that monitors the controller directly at the kernel layer using evtest.

1. Create or open the file:
```bash
sudo nano /etc/systemd/system/xbox-steam.service
```
⚠️ Paste the following code and remember to change YOUR_USERNAME to your actual username ⚠️
```Ini, TOML
[Unit]
Description=Steam Big Picture Trigger
After=systemd-udevd.service

[Service]
Type=simple
# NOTE: Users should replace 'YOUR_USERNAME' with their actual username
ExecStart=/bin/bash /home/YOUR_USERNAME/run_steam.sh listen
Restart=always
RestartSec=3

[Install]
WantedBy=basic.target
```
(Make sure to replace YOUR_USERNAME with your actual Linux username!)

2. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

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
# Replace these with your actual username and UID (run 'id' in terminal)
USER_NAME="YOUR_USERNAME"
USER_ID="1000"

# Verify these by running 'echo $DISPLAY' and 'echo $WAYLAND_DISPLAY' in your terminal
DISPLAY_VAR=":1"
WAYLAND_VAR="wayland-1"

# The name of your controller (or a unique keyword from its name)
TARGET_DEV_NAME="Microsoft X-Box 360 pad"

# The button code and name you want to trigger Steam you we got earlier with evtest

# For example:
# Event: time 1717968600.123456, type 1 (EV_KEY), code 316 (BTN_MODE), value 1
# Then TARGET_BTN_CODE should be "316" and TARGET_BTN_NAME should be "BTN_MODE"  
TARGET_BTN_CODE="316"
TARGET_BTN_NAME="BTN_MODE"
# =====================

SCRIPT_PATH="$(realpath "$0")"

# If started with "listen", act as the background listener
if [ "$1" == "listen" ]; then
    echo "Starting listener..."

    # Loop until a controller is found
    while true; do
        # Smart detection: Try the configured name first (case-insensitive)
        EVENT_NUMS=$(awk -v name="$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=1} $0 ~ name {cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if($i~/event/) print $i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+')
        
        # Fallback to generic keywords if the specific name isn't found
        if [ -z "$EVENT_NUMS" ]; then
            EVENT_NUMS=$(awk 'BEGIN{IGNORECASE=1} $0 ~ /xbox|pad|controller|joystick/ {cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if($i~/event/) print $i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+')
        fi

        if [ -n "$EVENT_NUMS" ]; then
            break
        fi
        echo "No controller found yet. Retrying in 5 seconds..."
        sleep 5
    done

    # Start a parallel background listener in a subshell for EACH matching event node
    for NUM in $EVENT_NUMS; do
        echo "Listening on /dev/input/event$NUM"
        (
            evtest /dev/input/event$NUM 2>/dev/null | while read -r line; do
                if echo "$line" | grep -q "code $TARGET_BTN_CODE ($TARGET_BTN_NAME), value 1"; then
                    /bin/bash "$SCRIPT_PATH" trigger &
                fi
            done
        ) &
    done

    # Keep the main listener loop alive forever
    while true; do
        sleep 60
    done
fi

# --- TRIGGER EXECUTION ---
# Redirect logs to the user's home directory
exec >> "/home/$USER_NAME/steam_error.log" 2>&1
echo "========================================="
echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
echo "Timestamp: $(date)"
echo "-----------------------------------------"

# Check for existing Steam processes for the specified user
PID_LIST=$(pgrep -u "$USER_NAME" -x "steam")

if [ -n "$PID_LIST" ]; then
    echo "Status: Steam is already running! Triggering Big Picture via XDG..."
    sudo -u "$USER_NAME" env DISPLAY="$DISPLAY_VAR" WAYLAND_DISPLAY="$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/$USER_ID" dbus-run-session xdg-open "steam://open/bigpicture" >/dev/null 2>&1 &
else
    echo "Status: Steam is not running. Launching Big Picture Mode from scratch..."
    sudo -u "$USER_NAME" env DISPLAY="$DISPLAY_VAR" WAYLAND_DISPLAY="$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/$USER_ID" nohup steam -bigpicture >/dev/null 2>&1 &
fi
echo "=== TRIGGER COMPLETE ==="
echo "========================================="
```
3. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

### 5. Permissions & Activation

Make the script executable, reload systemd configurations, and enable the service:

```bash
# Make the script executable (adjust path if needed)
chmod +x ~/run_steam.sh

# Enable and start the new systemd service
sudo systemctl daemon-reload
sudo systemctl enable --now xbox-steam.service
```

### Troubleshooting

If Steam doesn't open when you press the button, check the generated log file to see what went wrong:
```bash
cat ~/steam_error.log
```

To check if the service successfully located your controller and is actively running, use:
```bash
sudo systemctl status xbox-steam.service
```
(Press the Xbox button and verify it matches BTN_MODE and successfully executes the bash command).
