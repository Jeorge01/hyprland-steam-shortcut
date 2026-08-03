# How It Works

Architecture and functional description of the Hyprland Steam Shortcut. This
document explains why the project exists, how the pieces fit together, and what
happens in the background from a button press to Steam Big Picture Mode opening.

---

## 1. The problem

Hyprland (and Wayland compositors in general) is built on libinput and treats
game controllers as keyboards. They register as `*-keyboard` devices with no
reliable way to distinguish them from a real keyboard at the compositor level.
On top of that, games typically open the joystick device directly
(`/dev/input/js*`) without going through the compositor at all.

So there is no Hyprland bind for "this controller button". This project works
around that by reading raw input events directly from `/dev/input/event*` with
`evtest`, outside the compositor, and triggering Steam Big Picture Mode through
a background systemd user service.

## 2. Overview

```
 hss (bind-manager.sh)
   │  calibration → bind saved as <device-id>.conf
   ▼
 xbox-steam@<device-id>.service   (systemd user template unit)
   │  exec run_steam.sh listen <device-id>
   ▼
 run_steam.sh listen
   │  spawns  sudo evtest /dev/input/eventN  (root)
   ▼
 button press → run_steam.sh trigger
   │  finds the Steam window / current workspace
   ▼
 Steam Big Picture Mode
```

## 3. Components

### `install.sh` — the installer

Installs dependencies (`evtest`, `gum`), loads the xpad driver (auto-load on
boot), creates the systemd template unit, writes the sudoers rules, installs
the root helper `/usr/local/sbin/hss-evtest-stop`, deploys the scripts to
`~/.local/share/hss/`, creates the `hss` link in `~/.local/bin/`, and launches
the Bind Manager. Re-running it is idempotent (existing files are overwritten,
nothing is duplicated).

### `bind-manager.sh` — the UI (`hss`)

An interactive menu with three options:

- **Bind device** — calibrates and installs the button trigger (single or
  combo mode).
- **Show bound devices** — shows, toggles or removes binds. Toggling
  starts/stops the matching `xbox-steam@<id>.service`.
- **Options** — *Remove all binds* (deletes every `.conf` file, keeps the
  program) or *Uninstall program* (removes everything).

### `run_steam.sh` — listener + trigger

One script, two modes:

- `run_steam.sh listen <device-id>` — runs as a systemd service. Reads the
  device's `.conf`, locates the matching `/dev/input/event*` nodes and spawns
  one `sudo evtest` process per node. If a node is exclusively grabbed by
  another process (input-remapper, Steam Input, hkdm, ...), the listener
  falls back to the grabber's forwarded virtual clone so the bind still works
  while the grabber keeps control. It re-evaluates the grab state while
  running: if a grabber starts or stops, the listener swaps between the
  physical device and the forwarded clone on its own. On disconnect it
  cleans up and re-scans the devices automatically. Grab/forward diagnostics
  (and which app holds the device, via the root helper's `--holders` mode)
  are logged under the same `hss-trigger` tag as the trigger, so
  `journalctl --user -t hss-trigger -f` shows the whole lifecycle.
- `run_steam.sh trigger` — runs on button press. Copies DISPLAY/Wayland
  environment into the service, focuses the Steam window or current workspace,
  and opens Big Picture Mode. Trigger output is logged to the systemd journal
  with the tag `hss-trigger`; follow it live with `journalctl --user -t hss-trigger -f`.

### `uninstall.sh` — the uninstaller

Removes binds or the entire installation (binds, service, sudoers rules, the
helper, scripts and logs).

## 4. Configuration and state

| Path | Contents |
|---|---|
| `~/.config/steam-shortcut/config` | Global config: `USER_NAME`, `USER_ID` |
| `~/.config/steam-shortcut/devices/<device-id>.conf` | Per-device bind: `TARGET_DEV_NAME`, `DEVICE_UNIQ`, `DEVICE_SERIAL`, `BIND_MODE`, button codes |
| `~/.local/share/hss/` | Deployed scripts (`bind-manager.sh`, `run_steam.sh`, `uninstall.sh`) |
| `~/.local/bin/hss` | Bind Manager launcher command |
| `~/.config/systemd/user/xbox-steam@.service` | Systemd template unit (instance = `<device-id>`) |
| `/etc/sudoers.d/xbox-steam-evtest` | NOPASSWD rules for `evtest` and the helper |
| `/usr/local/sbin/hss-evtest-stop` | Root helper that kills root `evtest` processes; `--holders` lists who holds a node (`fuser`) |
| `/tmp/xbox-steam-<id>-pids.txt` | Listener subshell PIDs (runtime) |
| `/tmp/xbox-steam-<id>-nodes.txt` | `eventN` nodes in use (runtime) |
| `/tmp/xbox-steam-calibrating` | Calibration lockfile (suppresses triggers) |

## 5. Device identification

A device's ID is the `VID-PID` from `evtest` (e.g. `045e-028e`). Since two
identical controllers would otherwise share the same bind, the ID gets a
per-instance suffix from the device: the `U: Uniq=` value in
`/proc/bus/input/devices` or the USB serial number (`DEVICE_SERIAL`),
normalized to `<vid>-<pid>-<instance>` (e.g. `045e-028e-flydigi-direwolf-4`).

`device_events()` in `run_steam.sh` matches `Vendor`/`Product` against
`/proc/bus/input/devices`, filters by Uniq/serial or device name, and excludes
Steam Input clones (empty `Phys`). That is why the service picks up the
controller dynamically, even when the `eventN` number changes between reboots.

## 6. Coexisting with other apps that grab the controller

Input devices are *not* exclusive by default: the kernel broadcasts each event
to every process that has the device node open. That is why Steam and this
listener can read the same controller at the same time.

Some apps opt out of that. Tools like input-remapper, Steam Input and hkdm
issue an exclusive grab (`EVIOCGRAB`) on the device. From then on the kernel
delivers events **only** to the grabbing process — every other reader
(including this listener's `evtest`) silently receives nothing. A grab is
fundamental to those tools: they must swallow the original events so games do
not see both the original and the remapped ones.

This listener handles that situation instead of breaking:

1. **Detect the grab.** `node_is_grabbed()` probes each physical node with a
   brief `evtest --grab`; if the grab is denied, another process holds it.
2. **Fall back to the grabber's clone.** Grabbers that swallow the device still
   re-emit the events nothing remapped, through a virtual *forwarded* clone
   (e.g. input-remapper's `input-remapper <name> forwarded`, with
   `Phys=py-evdev-uinput` and the same VID/PID as the original).
   `forwarded_events()` finds those nodes and the listener reads them instead.
3. **Keep watching.** While running, the listener compares the current set of
   forwarded clones every few seconds. If a grabber starts or stops, it
   re-evaluates and swaps between the physical device and the clone on its own.
4. **Warn when it cannot help.** If the device is grabbed but no forwarded clone
   exists, a warning is logged to the journal with hints
   (`fuser -v /dev/input/eventN`, `sudo systemctl stop input-remapper`).

All grab/forward transitions — and the app holding the device, identified via
the root helper's `--holders` mode (`fuser`) — are logged under the
`hss-trigger` tag, so `journalctl --user -t hss-trigger -f` shows the whole
lifecycle alongside trigger events.

**Limitation:** if a grabber *remaps* the very button this listener is bound to,
that button never reaches the forwarded clone — it is consumed by the grabber.
Use different buttons in each tool, or disable the grabber for that device.

## 7. Listener lifecycle — and why the helper exists

The listener runs `sudo evtest /dev/input/eventN`, i.e. as **root**, inside a
*user* systemd service's cgroup. A user systemd cannot kill root processes —
`kill control group` fails with *Operation not permitted*. That caused two
symptoms:

1. **Toggling a bind off left the listener running.** The service showed
   `inactive` but the root `evtest` process kept running, so the bind still
   triggered Steam.
2. **`disable --now` hung.** Without explicit cleanup the cgroup never
   emptied, and systemd waited in `stop-sigterm` until `TimeoutStopSec`
   (90 s) elapsed — the menu showed "Toggling bind…" the whole time.

The fix is to always kill the root listeners *explicitly*:

- `run_steam.sh` writes its `eventN` nodes to `nodes.txt` next to `pids.txt`.
- `cleanup_listeners()` kills the listener subshells via `pids.txt` and then
  calls `sudo -n /usr/local/sbin/hss-evtest-stop $(cat nodes.txt)`, which
  `pkill`s `evtest /dev/input/<node>` as root.
- Trap: `trap 'cleanup_listeners; exit 0' EXIT INT TERM` — when the service
  receives SIGTERM, the script cleans up and exits, so systemd can stop
  immediately.
- The unit's `ExecStop` does the same on `systemctl stop`, so cleanup works
  even if the script hangs.
- `bind-manager.sh` toggles binds with `disable --now` followed by an explicit
  helper call, and *Remove all binds* / uninstall kill the root listeners and
  delete the `.conf` files.

## 8. The trigger path (button press → Steam)

1. `evtest` reports `code <N> value 1`. In combo mode only the trigger button
   fires while the modifier button is held; in single mode a single button
   suffices.
2. `run_steam.sh trigger` starts and reads `WAYLAND_DISPLAY`/`DISPLAY` from the
   service environment (with a fallback to the compositor process's
   `/proc/<pid>/environ`).
3. The script finds the Steam window's workspace via `hyprctl clients`, or uses
   the current workspace if Steam is not running yet.
4. `hyprctl eval` moves focus via `hl.dsp.focus` / `cursor.move_to_corner`,
   then Steam is launched with `steam steam://open/bigpicture` (or
   `systemd-run --user steam -bigpicture` if Steam is not running).

## 9. Troubleshooting

- **No button press registered** — another process may hold an exclusive grab
  on the device: input-remapper (`sudo systemctl stop input-remapper`), Steam
  Input, `hkdm` (`sudo pacman -R hkdm`), or check `sudo fuser /dev/input/event*`.
  The listener detects grabs automatically and falls back to the grabber's
   forwarded virtual device, and keeps watching so it swaps back when the grabber
   stops. If no forwarded clone exists it logs a warning to the journal. The
   diagnostics under `journalctl --user -t hss-trigger -f` report when the device
   is grabbed, which forwarded clone is used instead, and which app holds the
   device. Note
  that a grabber that *remaps* the bound button (e.g. input-remapper mapping
  `BTN_MODE` to `KEY_F24`) swallows that button, so the forwarded fallback only
  works for buttons the grabber leaves untouched — use different buttons in each
  tool.
- **Steam does not open** — check `journalctl --user -t hss-trigger -f` for errors.
- **Controller reconnects but the service does not pick it up** — the listener
  re-scans devices automatically; otherwise `systemctl --user restart
  xbox-steam@<device-id>.service`.
- **A bind does not toggle off** — verify that
  `/usr/local/sbin/hss-evtest-stop` exists and the sudoers rule is in place
  (`sudo -l`), and that `~/.config/systemd/user/xbox-steam@.service` contains
  the new `ExecStop`: run `systemctl --user daemon-reload` after the unit is
  updated.
