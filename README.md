# Hyprland Steam Shortcut (Xbox/Guide Button Fix)

A guide and script to map the Xbox/Guide (Home/Mode) button on your controller (e.g., Flydigi, Xbox controllers) to launch **Steam Big Picture** globally in a modern Hyprland/Wayland session.

---

## 1. Prerequisites & Installation

To capture controller inputs globally (even when no window is focused) and bypass Wayland's strict security layers, we need a driver, an input testing utility, and a background hotkey daemon.

Install the following packages using your package manager (e.g., `pacman` on Arch Linux):

```bash
# 1. xpad - Standard Xbox controller driver (usually built into the kernel, make sure it's not blacklisted)
# 2. hkdm - HotKey Daemon for input devices (intercepts hardware buttons globally)
# 3. evtest - Utility to monitor input events and find button names

sudo pacman -S evtest

# If hkdm is not in the official repositories, install it via the AUR:
yay -S hkdm
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

## 3. Configure HKDM (steam.toml)

HKDM listens at the hardware level. We will create a dedicated configuration file to map our Steam shortcut.

1. Create or open the file:
```bash
sudo nano /etc/hkdm/config.d/steam.toml
```
2. Paste the following configuration:
```Ini, TOML
[general]
allow_all_devices = true

[[events]]
key_state = "pressed"
keys = ["BTN_MODE"]
command = "/bin/bash /home/$USER/run_steam.sh"
```
3. Save and exit (Ctrl + O, Enter, Ctrl + X).

## 4. Create the Automation Script (run_steam.sh)

Because hkdm runs as root in the background, this script safely bridges the command into your active graphical environment (jeorge01) by passing the exact environment variables needed for both Wayland (wayland-1) and Xwayland (DISPLAY=:1).

It also includes a safety check so that hitting the button while a game is running will not restart or interrupt Steam.
