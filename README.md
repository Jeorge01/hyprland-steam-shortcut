# Hyprland Steam Shortcut

Hyprland's built-in `bind` only supports keyboard keys and mouse buttons while game controllers are not distinguishable at the compositor level. This service solves that by mapping any input device button to launch Steam Big Picture Mode via raw `evtest` events outside the compositor.

<img src="https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main/assets/showcase.png" width="2560" height="1440" alt="Showcase" />

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat&logo=bookstack&logoColor=white" alt="License"></a>
  <img src="https://img.shields.io/badge/language-Shell_Script-4EAA25?style=flat&logo=gnubash&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/platform-Linux-00C474?style=flat&logo=linux&logoColor=white" alt="Platform">
  <a href="https://github.com/Jeorge01/hyprland-steam-shortcut/commits/main"><img src="https://img.shields.io/github/last-commit/Jeorge01/hyprland-steam-shortcut?style=flat&label=last%20update&color=informational" alt="Last Commit"></a>
</p>

## Supported Distros
<p>
  <img src="assets/archlinux.svg" width="20" height="20" align="left" />
  <strong>Arch Linux</strong> (pacman) 
</p>
<p>
  <img src="assets/fedora.svg" width="20" height="20" align="left" />
  <strong>Fedora</strong> (dnf)
</p>

## Requirements
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

<br>

# Installation

The one-line installer downloads the Bind Manager, sets up the systemd user service, sudoers rule, a root cleanup helper for stopping evtest listeners, and the driver config, and installs a `hss` command for managing everything later.

### Quick Installation (Recommended)
Open your terminal and run (works on both Arch Linux and Fedora):

```bash
curl -sL https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main/install.sh | bash
```
The installer finishes by launching the Bind Manager. After that, run `hss` anytime to open it again.

You could also clone or download the repository and run `install.sh` like this:

```bash
# Clone the repository
git clone https://github.com/Jeorge01/hyprland-steam-shortcut.git
cd hyprland-steam-shortcut

# Run the installer
./install.sh
```

## Why This Exists

Hyprland's input system, like all Wayland compositors built on libinput, treats game controllers as keyboards. They register as `*-keyboard` devices with no reliable way to distinguish them from a real keyboard at the compositor level.

In [Hyprland#1211](https://github.com/hyprwm/Hyprland/issues/1211), **vaxerski** said:

> *"I am unsure how I would distinguish controllers from keyboards / mice. I think they're just plain old keyboards?"*

Even if detection were possible, games typically open the joystick device directly (`/dev/input/js*`) without going through the compositor at all. As **gulafaran** noted:

> *"Some apps/games open the joystick device directly without even going through the compositor [...] which is why most compositors lack this feature."*

This project works around both limitations by reading raw input events via `evtest` directly from `/dev/input/event*`, outside the compositor, and triggering Steam Big Picture Mode through a background systemd user service.

## Interactive Menu

Running `hss` opens an interactive menu with three options:

- **Bind device** - Calibrate and install the button trigger
- **Show bound devices** - Manage, toggle or remove a bind
- **Options** - Uninstall binds or the whole program:
  - **Remove all binds** - Remove every bind, keep the program
  - **Uninstall program** - Remove the whole installation (binds, service, sudoers, scripts, logs)

Behind the scenes, the installer uses [`evtest`][evtest] to capture raw input events and [`gum`][gum] for the interactive prompts — both are automatically installed if missing.

<a href="HOW_IT_WORKS.md" target="_blank"><kbd> <br> How it works <br> </kbd></a>
<a href="https://gitlab.freedesktop.org/libevdev/evtest" target="_blank"><kbd> <br> evtest <br> </kbd></a>
<a href="https://github.com/charmbracelet/gum" target="_blank"><kbd> <br> gum <br> </kbd></a>

## License
This project is licensed under the [MIT License](LICENSE).
