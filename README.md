![Logo](assets/hss.svg)

### Automated background service that maps any designated device input to launch Steam Big Picture Mode globally in a Hyprland/Wayland session.

---

## Installation

You can install or update the shortcut trigger automatically using the following command.

### One-line Installer (Recommended)
Open your terminal and run (works on both Arch Linux and Fedora):

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

To capture device inputs globally (even when no window is focused) and bypass Wayland's strict security layers, we need an input testing utility and a background system service.
Install the necessary utility depending on your distribution:

```bash
# 1. xpad - Standard Xbox controller driver (usually built into the kernel, make sure it's not blacklisted)
# 2. evtest - Utility to monitor input events and find button names
```

### On Arch:
```bash
sudo pacman -S evtest
```

### On Fedora:
```bash
sudo dnf install evtest
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
To prevent having to do this manually every time you restart your system, create a configuration file that tells your system to always load xpad at startup:
```bash
echo "xpad" | sudo tee /etc/modules-load.d/xpad.conf
```

### 2. Granting Secure Input Access
To let the user-level script monitor hardware events without prompting for passwords, add an exception rule for `evtest`:
```bash
# Create the secure exception file
echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/evtest" | sudo tee /etc/sudoers.d/xbox-steam-evtest
sudo chmod 440 /etc/sudoers.d/xbox-steam-evtest
```

### 3. Identify the Button Name using evtest

Before writing the configuration, we must find out exactly what the system calls your custom shortcut button.

1. Run evtest as root:
```bash
sudo evtest
```
2. You will see a list of all available input devices. Locate your device (e.g., Microsoft X-Box 360 pad or Flydigi), type its corresponding number, and press Enter.
3. Press the designated button you wish to use as a shortcut on your device (e.g., Xbox/Guide, Share, or a back paddle).
4. Look at the terminal output. Search for (EV_KEY) and the name inside the parentheses. For example:

```Plaintext
Event: time 1717968600.123456, type 1 (EV_KEY), code 316 (BTN_MODE), value 1
```
⚠️ Save this somewhere since we are using these values as variables later... ⚠️

### 4. Create the Systemd Service

Instead of using a desktop-level hotkey daemon (which Wayland often blocks), we create a lightweight systemd service that monitors the device directly at the kernel layer using evtest.

1. Create or open the file:
```bash
nano ~/.config/systemd/user/xbox-steam.service
```

```Ini, TOML
[Unit]
Description=Steam Big Picture Trigger
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash %h/run_steam.sh listen
KillMode=process
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

2. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

### 5. Create the Automation Script (run_steam.sh)

This script does two things:
1. When started by systemd, it dynamically finds the correct input event for the device and listens for the button press.
2. When the button is pressed, it safely bridges the command into your active graphical session (Wayland/Hyprland) with correct display variables.

Create the script in your home directory:
```bash
nano ~/run_steam.sh
```

⚠️ Paste the following code and remember to change the variables ⚠️

```bash
#!/bin/bash

# === CONFIGURATION ===
# The name of your device (or a unique keyword from its name)
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

            echo "Waiting for your specific physical device ($TARGET_DEV_NAME) to initialize..."
            sleep 2
        done
        
        for NUM in $EVENT_NUMS; do
            until [ -r "/dev/input/event$NUM" ]; do
                echo "Waiting for /dev/input/event$NUM to become readable..."
                sleep 0.2
            done
        done

        echo "Your calibrated device is ready! Initializing listener..."

        LISTENER_PIDS=""

        for NUM in $EVENT_NUMS; do
            if [ -e "/dev/input/event$NUM" ]; then
                echo "Listening on /dev/input/event$NUM"
                (
                    sudo evtest /dev/input/event$NUM 2>/dev/null | while read -r line; do
                        if echo "$line" | grep -q "code $TARGET_BTN_CODE ($TARGET_BTN_NAME), value 1"; then
                            /bin/bash "$SCRIPT_PATH" trigger &
                        fi
                    done
                ) &
                LISTENER_PIDS="$LISTENER_PIDS $!"
            fi
        done

        while true; do
            sleep 2
            STILL_CONNECTED=1

            for NUM in $EVENT_NUMS; do
                if [ ! -e "/dev/input/event$NUM" ]; then
                    STILL_CONNECTED=0
                    break
                fi
            done
            
            if [ $STILL_CONNECTED -eq 0 ]; then
                echo "⚠️ Device disconnected! Cleaning up background processes..."
                for pid in $LISTENER_PIDS; do
                    kill $pid 2>/dev/null
                done
                echo "Re-scanning hardware..."
                break
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
if [ "$1" == "trigger" ]; then
    exec >> "$HOME/steam_error.log" 2>&1
    echo "========================================="
    echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
    echo "Timestamp: $(date)"
    echo "─────────────────────────────────────────"

    # Fetch environment variables dynamically from the systemd user session
    export WAYLAND_DISPLAY=$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
    export DISPLAY=$(systemctl --user show-environment | grep '^DISPLAY=' | cut -d= -f2)
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    # Fallback if systemd started before the compositor environment was fully registered
    if [ -z "$WAYLAND_DISPLAY" ]; then
        COMPOSITOR_PID=$(pgrep -u "$USER" -x "Hyprland|sway|wayfire|gnome-shell|kwin_wayland" | head -n 1)
        if [ -n "$COMPOSITOR_PID" ]; then
            export WAYLAND_DISPLAY=$(grep -z '^WAYLAND_DISPLAY=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export DISPLAY=$(grep -z '^DISPLAY=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export HYPRLAND_INSTANCE_SIGNATURE=$(grep -z '^HYPRLAND_INSTANCE_SIGNATURE=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
        fi
    fi

    [ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY="wayland-0"
    [ -z "$DISPLAY" ] && export DISPLAY=":0"

    CURRENT_ACTIVE_WS=$(hyprctl monitors | awk '/active workspace:/ {print $3; exit}')
    TARGET_WORKSPACE=${CURRENT_ACTIVE_WS:-"1"}
    echo "Current active workspace in focus: $TARGET_WORKSPACE"

    PID_LIST=$(pgrep -u "$USER" -x "steam")

    if [ -n "$PID_LIST" ]; then
        echo "Steam is running. Searching for Steam window workspace..."
        
        STEAM_WS=$(hyprctl clients | awk '
            /^Window/ { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                is_steam = 0
                ws = ""
            }
            /workspace:/ { ws = $2 }
            /class: [Ss]team/ { is_steam = 1 }
            END { 
                if (is_steam && ws != "") { last_steam_ws = ws }
                print (last_steam_ws != "") ? last_steam_ws : "unknown"
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

    echo "Forcing focus to Hyprland Workspace $TARGET_WORKSPACE via modern Lua eval..."
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $TARGET_WORKSPACE }))"
    hyprctl eval "hl.dispatch(hl.dsp.window.focus({ window = 'class:[Ss]team' }))" 2>/dev/null || true
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 2, window = 'class:[Ss]team' }))" 2>/dev/null || true

    if [ -n "$PID_LIST" ]; then
        echo "Status: Triggering Big Picture..."
        steam steam://open/bigpicture >/dev/null 2>&1 &
    else
        echo "Status: Launching Big Picture from scratch..."
        systemd-run --user --scope --unit=steam-app steam -bigpicture >/dev/null 2>&1 &
    fi
    echo "=== TRIGGER COMPLETE ==="
    echo "========================================="
fi
```
3. Save and exit (`Ctrl + O`, `Enter`, `Ctrl + X`).

### 6. Permissions & Activation

Make the script executable, reload systemd configurations, and enable the service:

```bash
# Make the script executable (adjust path if needed)
chmod +x ~/run_steam.sh

# Enable and start the new systemd service
systemctl --user daemon-reload
systemctl --user enable --now xbox-steam.service
loginctl enable-linger $(whoami)
```

### Troubleshooting

If Steam doesn't open when you press the button, check the generated log file to see what went wrong:
```bash
cat ~/steam_error.log
```

To check if the service successfully located your controller and is actively running, use:
```bash
systemctl --user status xbox-steam.service
```

## License
This project is licensed under the [MIT License](LICENSE).
