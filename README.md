# Hyprland Steam Shortcut (Xbox/Guide Button Fix)

A guide and script to map the Xbox/Guide (Home/Mode) button on your controller (e.g., Flydigi, Xbox controllers) to launch **Steam Big Picture** globally in a modern Hyprland/Wayland session.

---

## 1. Prerequisites & Installation

To capture controller inputs globally (even when no window is focused) and bypass Wayland's strict security layers, we need a driver, an input testing utility, and a background hotkey daemon.

Install the following packages using your package manager (e.g., `pacman` on Arch Linux):

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
After=multi-user.target

[Service]
Type=simple
ExecStart=/bin/bash /home/YOUR_USERNAME/run_steam.sh listen
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
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
Paste the following code:
```bash
#!/bin/bash

# === CONFIGURATION ===
# Replace these with your actual username and UID (run 'id' in terminal if unsure)
USER_NAME="YOUR_USERNAME"
USER_ID="1000"
DISPLAY_VAR=":0"
WAYLAND_VAR="wayland-0"
# =====================

# If started with "listen", act as the background listener
if [ "$1" == "listen" ]; then
    # Dynamically find the correct event number for the Xbox controller
    EVENT_NUM=$(awk '/Name="Microsoft X-Box 360 pad"/{cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if($i~/event/) print $i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+' | head -n1)
    
    if [ -z "$EVENT_NUM" ]; then
        echo "Could not find Microsoft X-Box 360 pad in the system!" >&2
        exit 1
    fi
    
    # Listen to the device and trigger the script when BTN_MODE (code 316) is pressed
    evtest /dev/input/event$EVENT_NUM | while read -r line; do
        if echo "$line" | grep -q 'code 316 (BTN_MODE), value 1'; then
            /bin/bash /home/$USER_NAME/run_steam.sh trigger
        fi
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
exec > /home/$USER_NAME/steam_error.log 2>&1

echo "=== SCRIPT TRIGGERED BY SYSTEMD ==="
echo "Date/Time: $(date)"

if pgrep -u $USER_NAME -x "steam" > /dev/null; then
    echo "Steam is already running! Sending command to open Big Picture Mode..."
    su - $USER_NAME -c "DISPLAY=$DISPLAY_VAR WAYLAND_DISPLAY=$WAYLAND_VAR XDG_RUNTIME_DIR=/run/user/$USER_ID steam steam://open/bigpicture &"
else
    echo "Steam is not running. Launching Big Picture Mode..."
    su - $USER_NAME -c "DISPLAY=$DISPLAY_VAR WAYLAND_DISPLAY=$WAYLAND_VAR XDG_RUNTIME_DIR=/run/user/$USER_ID steam -bigpicture &"
fi
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
