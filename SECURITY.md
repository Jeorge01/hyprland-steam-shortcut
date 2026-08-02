# Security Policy

This project is a set of shell scripts that interact with system-level services:
it installs sudoers rules, a root helper (`/usr/local/sbin/hss-evtest-stop`),
a systemd user service and reads raw input events via `evtest`. Issues in
these areas deserve careful handling.

## Reporting a Vulnerability

**Do not open a public issue with security details.** Please report
vulnerabilities privately so they can be addressed before disclosure.

Use GitHub's **Private vulnerability reporting** on this repository:

- Go to the repository's *Security* tab → *Advisories* → *New draft security advisory*.
- Alternatively, use the *Report a vulnerability* button on the repository
  page if private reporting is enabled.

Please include:

- Affected files / scripts and versions
- Steps to reproduce (if known)
- Impact (what an attacker could do, and under what assumptions — e.g. does
  it require local access already?)
- Any suggested fix

## Public vs private

- **Report privately** anything that could be *exploited*: code execution via
  the installer, sudoers/privilege escalation, symlink or path handling in
  `/tmp`, unsafe handling of device names or config values, and so on.
- **Open a regular issue** for general bugs, "Steam doesn't open", device
  detection problems, feature requests and usage questions.
- **Duplicate reports** of the same vulnerability are consolidated in the same
  advisory thread — you do not need to open a public issue to signal that
  something has already been reported. Wait for the fix; discussion in public
  issues is welcome once the fix and advisory have been published.
- If a private report turns out to be a non-security bug, it will be
  acknowledged as such and you will be asked to re-file it as a regular issue.

## Response

- Reports are acknowledged as soon as possible.
- A fix and a coordinated public advisory are typically preferred over an
  immediate full disclosure.
- If you have not received an acknowledgement within **30 days**, you may
  open a public issue referencing the advisory number so it cannot be
  silently dropped.

## Scope

The following are the highest-value targets and are in scope:

- `install.sh` / `uninstall.sh` (curl|bash installer, sudoers handling)
- The sudoers rules in `/etc/sudoers.d/xbox-steam-evtest`
- `/usr/local/sbin/hss-evtest-stop` (root helper, `pkill` usage)
- `run_steam.sh` (input event handling, systemd service, trigger execution)
- `bind-manager.sh` (config handling, service management)

Low-risk, non-security bugs are handled through the regular issue tracker.
