# Hyprland Steam Shortcut

Automated background service that maps any designated device input to launch Steam Big Picture Mode globally in a Hyprland/Wayland session.

<img src="https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main/assets/showcase.png" width="2560" height="1440" alt="Showcase" />

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
### Interactive Menu

When you run the installer, you'll see an interactive menu powered by [gum](https://github.com/charmbracelet/gum):

- **Bind device** — Calibrate and install the button trigger
- **Unbind** — Remove the installation completely (service, sudoers, scripts, logs)

`gum` is automatically installed if missing.

For a step-by-step manual installation:

**[<kbd> <br> Manual <br> </kbd>](MANUAL.md)**

## License
This project is licensed under the [MIT License](LICENSE).
