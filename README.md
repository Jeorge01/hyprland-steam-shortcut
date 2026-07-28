# Hyprland Steam Shortcut

Automated background service that maps any designated device input to launch Steam Big Picture Mode globally in a Hyprland/Wayland session.

<img src="assets/showcase.png" alt="Showcase" style="border-radius: 12px;" />

---

## Requirements

<table style="border-collapse: collapse; border: none;">
  <tr>
    <td align="center" style="border: none; padding: 2px 8px 2px 0;"><img src="assets/systemd.svg" height="20" style="vertical-align: middle;" /></td>
    <td style="border: none; padding: 2px 0;"><strong>Systemd</strong> — for the background user service</td>
  </tr>
  <tr>
    <td align="center" style="border: none; padding: 2px 8px 2px 0;"><img src="assets/archlinux.svg" height="20" style="vertical-align: middle;" /></td>
    <td style="border: none; padding: 2px 0;"><strong>Arch Linux</strong> (pacman) or <img src="assets/fedora.svg" height="20" style="vertical-align: middle;" /> <strong>Fedora</strong> (dnf)</td>
  </tr>
  <tr>
    <td align="center" style="border: none; padding: 2px 8px 2px 0;"><img src="assets/hyprland.svg" height="20" style="vertical-align: middle;" /></td>
    <td style="border: none; padding: 2px 0;"><strong>Hyprland</strong> — workspace focus and Steam window detection via <code>hyprctl</code></td>
  </tr>
  <tr>
    <td align="center" style="border: none; padding: 2px 8px 2px 0;"><img src="assets/steam.svg" height="20" style="vertical-align: middle;" /></td>
    <td style="border: none; padding: 2px 0;"><strong>Steam</strong> — installed on your system</td>
  </tr>
</table>

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

For a step-by-step manual installation, see [MANUAL.md](MANUAL.md).

## License
This project is licensed under the [MIT License](LICENSE).
