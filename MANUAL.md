# Manual Installation

Step-by-step instructions for setting up the Steam Big Picture trigger manually.

---

## Supported Distros
<p>
  <img src="assets/archlinux.svg" width="20" height="20" align="left" />
  <strong>Arch Linux</strong> (pacman) 
</p>
<p>
  <img src="assets/fedora.svg" width="20" height="20" align="left" />
  <strong>Fedora</strong> (dnf)
</p>

## Prerequisites
<p>
  <img src="assets/systemd.svg" width="20" height="20" align="left" />
  <strong>systemd</strong> — for the background user service
</p>
<p>
  <img src="assets/hyprland.svg" width="20" height="20" align="left" />
  <strong>Hyprland</strong> — workspace focus and Steam window detection via <code>hyprctl</code>
</p>
<p>
  <img src="assets/steam.svg" width="20" height="20" align="left" />
  <strong>Steam</strong> — installed on your system
</p>

## 1. Install Dependencies

### evtest

Capture input events and identify button codes:

```bash
# Arch
sudo pacman -S evtest

# Fedora
sudo dnf install evtest
```

### xpad Driver

Ensure the standard Xbox controller driver is loaded:

```bash
# Load immediately
sudo modprobe xpad

# Load on boot
echo "xpad" | sudo tee /etc/modules-load.d/xpad.conf
```

---

## 2. Grant Sudo Permission for evtest

The listener runs as a user service but needs root to read `/dev/input/event*`. Add a sudoers exception:

```bash
echo "$(id -un) ALL=(ALL) NOPASSWD: /usr/bin/evtest" | sudo tee /etc/sudoers.d/xbox-steam-evtest
sudo chmod 440 /etc/sudoers.d/xbox-steam-evtest
```

---

## 3. Find Your Device and Button Codes

### Single Button Mode

```bash
sudo evtest
```

Select your controller from the list, then press the button you want to use. Note the output:

```
Event: time 1717968600.123456, type 1 (EV_KEY), code 316 (BTN_MODE), value 1
```

Save the **device name** (from the evtest list), **button code** (`316`), and **button name** (`BTN_MODE`).

### Combo Mode (Modifier + Trigger)

For a two-button combo (hold one button, press another), you need codes and names for both buttons. The listener detects the modifier held state and only fires when the trigger is pressed while the modifier is held.

---

## 4. Create the Automation Script

Create `~/run_steam.sh`:

```bash
nano ~/run_steam.sh
```

Paste the script below and update the configuration block with your values:

```bash
#!/bin/bash

# === CONFIGURATION ===
USER_NAME="$(whoami)"
TARGET_DEV_NAME="Microsoft X-Box 360 pad"

# Single mode: the button that triggers Steam
TARGET_BTN_CODE="316"
TARGET_BTN_NAME="BTN_MODE"

# Combo mode: modifier + trigger
BIND_MODE="single"                           # "single" or "combo"
MODIFIER_BTN_CODE="316"
MODIFIER_BTN_NAME="BTN_MODE"
TRIGGER_BTN_CODE="317"
TRIGGER_BTN_NAME="BTN_TRIGGER"
# =====================

SCRIPT_PATH="$(realpath "$0")"

if [ "$1" == "listen" ]; then
    echo "Starting listener..."

    while true; do
        until awk -v name="$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=0} index($0, "N: Name=\"" name) == 1' /proc/bus/input/devices >/dev/null 2>&1; do
            echo "Waiting for your specific controller ($TARGET_DEV_NAME) to initialize..."
            sleep 2
        done

        EVENT_NUMS=$(awk -v name="$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=0} index($0, "N: Name=\"" name) == 1 {cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if($i~/event/) print $i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+')

        for NUM in $EVENT_NUMS; do
            until [ -r "/dev/input/event$NUM" ]; do
                echo "Waiting for /dev/input/event$NUM to become readable..."
                sleep 0.2
            done
        done

        echo "Your calibrated device is ready! Initializing listener..."

        if systemctl is-active --quiet input-remapper 2>/dev/null; then
            echo "WARNING: input-remapper is running and may block button detection"
            echo "   Run: sudo systemctl stop input-remapper"
        fi

        echo "" > /tmp/xbox-steam-pids.txt
        LISTENER_PIDS=""

        for NUM in $EVENT_NUMS; do
            if [ -e "/dev/input/event$NUM" ]; then
                echo "Listening on /dev/input/event$NUM"
                (
                    sudo evtest /dev/input/event$NUM 2>/dev/null | while read -r line; do
                        if [ "$BIND_MODE" = "combo" ]; then
                            if echo "$line" | grep -q "code $MODIFIER_BTN_CODE.*value 1"; then
                                MODIFIER_HELD=1
                            fi
                            if echo "$line" | grep -q "code $MODIFIER_BTN_CODE.*value 0"; then
                                MODIFIER_HELD=0
                            fi
                            if echo "$line" | grep -q "code $TRIGGER_BTN_CODE.*value 1"; then
                                if [ "${MODIFIER_HELD:-0}" -eq 1 ]; then
                                    MODIFIER_HELD=0
                                    /bin/bash "$SCRIPT_PATH" trigger &
                                fi
                            fi
                        else
                            if echo "$line" | grep -q "code $TARGET_BTN_CODE ($TARGET_BTN_NAME), value 1"; then
                                /bin/bash "$SCRIPT_PATH" trigger &
                            fi
                        fi
                    done
                ) &
                LISTENER_PIDS="$LISTENER_PIDS $!"
                echo "$LISTENER_PIDS" > /tmp/xbox-steam-pids.txt
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
                echo "Device disconnected! Re-scanning..."
                for pid in $LISTENER_PIDS; do
                    kill $pid 2>/dev/null
                done
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
    echo "-----------------------------------------"

    export WAYLAND_DISPLAY=$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
    export DISPLAY=$(systemctl --user show-environment | grep '^DISPLAY=' | cut -d= -f2)
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

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

    PID_LIST=$(pgrep -u "$USER_NAME" -x "steam")

    if [ -n "$PID_LIST" ]; then
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
        fi
    else
        echo "Steam is not running. It will be launched on the current workspace ($TARGET_WORKSPACE)."
    fi

    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $TARGET_WORKSPACE }))"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'class:[Ss]team' }))" 2>/dev/null || true
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 2, window = 'class:[Ss]team' }))" 2>/dev/null || true

    if [ -n "$PID_LIST" ]; then
        steam steam://open/bigpicture >/dev/null 2>&1 &
    else
        systemd-run --user --scope --unit=steam-app steam -bigpicture >/dev/null 2>&1 &
    fi

    echo "=== TRIGGER COMPLETE ==="
    echo "========================================="
fi
```

Save and make it executable:

```bash
chmod +x ~/run_steam.sh
```

---

## 5. Create the Systemd Service

```bash
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/xbox-steam.service
```

```ini
[Unit]
Description=Steam Big Picture Trigger
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash %h/run_steam.sh listen
ExecStop=/bin/sh -c 'pid_file="/tmp/xbox-steam-pids.txt"; if [ -f "$pid_file" ]; then xargs kill -9 < "$pid_file" 2>/dev/null; rm -f "$pid_file"; fi'
KillMode=process
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

---

## 6. Enable and Start

```bash
systemctl --user daemon-reload
systemctl --user enable --now xbox-steam.service
loginctl enable-linger $(whoami)
```

---

## 7. Verify

```bash
# Check service status
systemctl --user status xbox-steam.service

# View logs
cat ~/steam_error.log
```

---

## Troubleshooting

### No button press detected

Other processes may hold an exclusive grab on your input device:

- **input-remapper** — `sudo systemctl stop input-remapper`
- **hkdm** — `sudo pacman -R hkdm`

Check what holds your input devices:

```bash
sudo fuser /dev/input/event*
```

### Steam doesn't open

Check the log for errors:

```bash
cat ~/steam_error.log
```

### Controller reconnects but service doesn't pick it up

The listener automatically re-scans when the device disconnects. If it doesn't, restart the service:

```bash
systemctl --user restart xbox-steam.service
```
