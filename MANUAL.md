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
  <strong>Systemd</strong> - for the background user service
</p>
<p>
  <img src="assets/hyprland.svg" width="20" height="20" align="left" />
  <strong>Hyprland</strong> - desktop / window manager
</p>
<p>
  <img src="assets/steam.svg" width="20" height="20" align="left" />
  <strong>Steam</strong> - installed on your system
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
echo "$(id -un) ALL=(root) NOPASSWD: /usr/bin/evtest" | sudo tee /etc/sudoers.d/xbox-steam-evtest
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

The trigger script (`run_steam.sh`) reads configuration from `~/.config/steam-shortcut/config`.

### Configuration File

Create the config file with your calibration values:

```bash
mkdir -p ~/.config/steam-shortcut
nano ~/.config/steam-shortcut/config
```

```ini
USER_NAME="$(whoami)"
TARGET_DEV_NAME="Microsoft X-Box 360 pad"
BIND_MODE="single"
TARGET_BTN_CODE="316"
TARGET_BTN_NAME="BTN_MODE"

# Combo mode (uncomment if using combo):
# MODIFIER_BTN_CODE="316"
# MODIFIER_BTN_NAME="BTN_MODE"
# TRIGGER_BTN_CODE="317"
# TRIGGER_BTN_NAME="BTN_TRIGGER"
```

### Download the Trigger Script

```bash
curl -sL https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main/run_steam.sh -o ~/run_steam.sh
chmod +x ~/run_steam.sh
```

> If you cloned the repository, copy the file instead:
> ```bash
> cp /path/to/repo/run_steam.sh ~/run_steam.sh
> chmod +x ~/run_steam.sh
> ```

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
ExecStop=/bin/sh -c 'pid_file="/tmp/xbox-steam-pids.txt"; if [ -f "$pid_file" ]; then xargs kill < "$pid_file" 2>/dev/null; rm -f "$pid_file"; fi'
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
