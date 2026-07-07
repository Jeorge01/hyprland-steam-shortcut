# Hyprland Steam Shortcut (Controller Button Trigger)

Automated background service that maps any designated controller button to launch Steam Big Picture Mode globally in a Hyprland/Wayland session.

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

Before writing the configuration, we must find out exactly what the system calls your custom shortcut button.

1. Run evtest as root:
```bash
sudo evtest
```
2. You will see a list of all available input devices. Locate your controller (e.g., Microsoft X-Box 360 pad or Flydigi), type its corresponding number, and press Enter.
3. Press the designated button you wish to use as a shortcut on your controller (e.g., Xbox/Guide, Share, or a back paddle).
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

# The button code and name you want to trigger Steam (get this via evtest).
# You can map this to ANY button on your device (e.g., Guide, Share, Back buttons).
TARGET_BTN_CODE="316"
TARGET_BTN_NAME="BTN_MODE"
# =====================

SCRIPT_PATH="$(realpath "$0")"

if [ "$1" == "listen" ]; then
    echo "Starting listener..."

    while true; do
        while true; do
            CHECK_NUMS=$(awk -v name="$TARGET_DEV_NAME" '
                BEGIN { RS="\n\n|--\n"; IGNORECASE=1 }
                $0 ~ "N: Name=\"" name "\"" && $0 ~ "P: Phys=.+" {
                    if (match($0, /Handlers=[^\n]+/)) {
                        handlers = substr($0, RSTART, RLENGTH);
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

            if [ -n "$CHECK_NUMS" ]; then
                EVENT_NUMS="$CHECK_NUMS"
                break
            fi

            echo "Waiting for your specific physical controller ($TARGET_DEV_NAME) to initialize..."
            sleep 2
        done
        
        for NUM in $EVENT_NUMS; do
            until [ -r "/dev/input/event$NUM" ]; do
                echo "Waiting for /dev/input/event$NUM to become readable..."
                sleep 0.2
            done
        done

        echo "Your calibrated controller is ready! Initializing listener..."

        LISTENER_PIDS=""

        for NUM in $EVENT_NUMS; do
            if [ -e "/dev/input/event$NUM" ]; then
                echo "Listening on /dev/input/event$NUM"
                (
                    evtest /dev/input/event$NUM 2>/dev/null | while read -r line; do
                        if echo "$line" | grep -q "code $TARGET_BTN_CODE ($TARGET_BTN_NAME), value 1"; then
                            /bin/bash "$SCRIPT_PATH" trigger &
                        fi
                    done
                ) &
                LISTENER_PIDS="$LISTENER_PIDS $!"
            fi
        done

        while [ -n "$LISTENER_PIDS" ]; do
            sleep 10
            ANY_ALIVE=0
            for pid in $LISTENER_PIDS; do
                if kill -0 $pid 2>/dev/null; then
                    ANY_ALIVE=1
                fi
            done
            
            if [ $ANY_ALIVE -eq 0 ]; then
                echo "⚠️ Controller disconnected. Re-scanning hardware..."
                break
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
if [ "$1" == "trigger" ]; then
    exec >> "/home/$USER_NAME/steam_error.log" 2>&1
    echo "========================================="
    echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
    echo "Timestamp: $(date)"
    echo "-----------------------------------------"

    # Get Hyprland instance signature
    HYPR_SIGNATURE=$(pgrep -u "$USER_NAME" -x Hyprland -a | grep -o 'HYPRLAND_INSTANCE_SIGNATURE=[^ ]*' | cut -d= -f2- | head -n1)
    if [ -z "$HYPR_SIGNATURE" ]; then
        HYPR_SIGNATURE=$(ls -dt /run/user/$USER_ID/hypr/* 2>/dev/null | head -n 1 | xargs basename 2>/dev/null)
    fi

    # Get current active workspace
    CURRENT_ACTIVE_WS=$(runuser -u "$USER_NAME" -- env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIGNATURE" XDG_RUNTIME_DIR="/run/user/$USER_ID" hyprctl monitors | awk '/active workspace:/ {print $3; exit}')
    
    TARGET_WORKSPACE=${CURRENT_ACTIVE_WS:-"1"}
    echo "Current active workspace in focus: $TARGET_WORKSPACE"

    PID_LIST=$(pgrep -u "$USER_NAME" -x "steam")

    if [ -n "$PID_LIST" ]; then
        echo "Steam is running. Searching for Steam window workspace..."
        
        STEAM_WS=$(runuser -u "$USER_NAME" -- env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIGNATURE" XDG_RUNTIME_DIR="/run/user/$USER_ID" hyprctl clients | awk '
            /^Window/ { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                is_steam = 0
                ws = ""
            }
            /class: [Ss]team/ || /initialClass: [Ss]team/ { 
                is_steam = 1 
            }
            /workspace: / {
                line = $0
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
        
        if [ -n "$STEAM_WS" ] && [ "$STEAM_WS" -eq "$STEAM_WS" ] 2>/dev/null; then
            TARGET_WORKSPACE="$STEAM_WS"
            echo "Found Steam on Workspace: $TARGET_WORKSPACE"
        else
            echo "Steam is running but no open window found yet. Staying on current workspace."
        fi
    else
        echo "Steam is not running. It will be launched on the current workspace ($TARGET_WORKSPACE)."
    fi

    echo "Forcing focus to Hyprland Workspace $TARGET_WORKSPACE via hyprctl eval..."
    HYPR_ERR=$(runuser -u "$USER_NAME" -- env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIGNATURE" XDG_RUNTIME_DIR="/run/user/$USER_ID" hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $TARGET_WORKSPACE }))" 2>&1)
    echo "Hyprctl eval output: ${HYPR_ERR:-"Success"}"

    if [ -n "$PID_LIST" ]; then
        echo "Status: Triggering Big Picture..."
        systemd-run --user --machine="$USER_NAME@.host" --collect env DISPLAY="$DISPLAY_VAR" WAYLAND_DISPLAY="$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/$USER_ID" dbus-run-session xdg-open "steam://open/bigpicture" >/dev/null 2>&1
    else
        echo "Status: Launching Big Picture from scratch..."
        systemd-run --user --machine="$USER_NAME@.host" --collect env DISPLAY="$DISPLAY_VAR" WAYLAND_DISPLAY="$WAYLAND_VAR" XDG_RUNTIME_DIR="/run/user/$USER_ID" steam -bigpicture >/dev/null 2>&1
    fi
    echo "=== TRIGGER COMPLETE ==="
    echo "========================================="
fi
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

## License
This project is licensed under the [MIT License](LICENSE).
