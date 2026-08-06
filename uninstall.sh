#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

MODE="${1:-all}"
case "$MODE" in
    binds|all) ;;
    *) MODE="all" ;;
esac

HYPR_BLUE=$'\e[38;2;94;204;227m'
HYPR_DARK_BLUE=$'\e[38;2;85;184;204m'
HYPR_DARKEST_BLUE=$'\e[38;2;72;162;180m'

GREEN=$'\e[38;2;94;227;149m'
YELLOW=$'\e[38;2;244;208;63m'
RED=$'\e[38;2;231;76;60m'
WHITE=$'\e[1;37m'
CLEAR=$'\e[0m'

K_DIM=$'\e[38;2;97;97;97m'
K_DIM2=$'\e[38;2;73;73;73m'

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/steam-shortcut"
DEVICES_DIR="$CONFIG_DIR/devices"
APP_DIR="$HOME/.local/share/hss"
HSS_BIN="$HOME/.local/bin/hss"

art_line() {
    local line="$1" out="" prev=0 i=0
    shift
    local -a colors=( "${HYPR_BLUE}" "${HYPR_DARK_BLUE}" "${HYPR_DARKEST_BLUE}" )
    for cut in "$@"; do
        out+="${colors[$((i % 3))]}${line:prev:cut-prev}"
        prev=$cut
        i=$((i + 1))
    done
    out+="${colors[$((i % 3))]}${line:prev}"
    printf '%s%s\n' "$out" "$CLEAR"
}

banner_binds() {
    echo -e "${HYPR_BLUE}"

    art_line "▄▖             ▄▖▜ ▜   ▌ ▘   ▌  " 4 7 13 17 19 23 26 30
    art_line "▙▘█▌▛▛▌▛▌▌▌█▌  ▌▌▐ ▐   ▛▌▌▛▌▛▌▛▘" 4 7 13 17 19 23 26 30
    art_line "▌▌▙▖▌▌▌▙▌▚▘▙▖  ▛▌▐▖▐▖  ▙▌▌▌▌▙▌▄▌ " 4 7 13 17 19 23 26 30
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "${HYPR_BLUE}" "Unb" "${HYPR_DARK_BLUE}" "in" "${HYPR_DARKEST_BLUE}" "d" "${HYPR_BLUE}" " al" "${HYPR_DARK_BLUE}" "l" "${HYPR_BLUE}" " dev" "${HYPR_DARK_BLUE}" "ic" "${HYPR_DARKEST_BLUE}" "es" "${CLEAR}"
    echo ""
}

banner_uninstall() {
    echo -e "${HYPR_BLUE}"

    art_line "▖▖  ▘    ▗   ▜ ▜   ▖▖▄▖▄▖" 7 13 17 23
    art_line "▌▌▛▌▌▛▌▛▘▜▘▀▌▐ ▐   ▙▌▚ ▚ " 7 13 17 23
    art_line "▙▌▌▌▌▌▌▄▌▐▖█▌▐▖▐▖  ▌▌▄▌▄▌" 7 13 17 23
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "${HYPR_BLUE}" "Unin" "${HYPR_DARK_BLUE}" "sta" "${HYPR_DARKEST_BLUE}" "ll" "${HYPR_BLUE}" " Pro" "${HYPR_DARK_BLUE}" "gr" "${HYPR_DARKEST_BLUE}" "am" "${CLEAR}"
    echo ""
}

confirm() {
    if command -v gum &>/dev/null; then
        gum confirm "$1" </dev/tty \
            --prompt.foreground "#E74C3C" \
            --selected.foreground "#FFFFFF" \
            --selected.background "#E74C3C" \
            --unselected.foreground "#CCCCCC" \
            --unselected.background "#2A2A2A" \
            --affirmative " Yes " \
            --negative " No "
    else
        echo -n "$1 (y/n): "
        read -r r </dev/tty
        [[ "$r" =~ ^[Yy]$ ]]
    fi
}

press_enter() {
    echo ""
    echo -e " ${K_DIM}enter${CLEAR} ${K_DIM2}continue${CLEAR}"
    printf '\033[?25l' >/dev/tty
    read -r -s -n1 </dev/tty || true
    printf '\033[?25h' >/dev/tty
}

BIND_COUNT=0

count_binds() {
    local conf count=0
    for conf in "$DEVICES_DIR"/*.conf; do
        [ -e "$conf" ] || continue
        count=$((count + 1))
    done
    BIND_COUNT=$count
}

remove_all_binds() {
    local conf id nf
    for conf in "$DEVICES_DIR"/*.conf; do
        [ -e "$conf" ] || continue
        id=$(basename "$conf" .conf)
        systemctl --user disable --now "hss-steam-trigger@$id.service" 2>/dev/null || true
    done
    systemctl --user stop 'hss-steam-trigger@*.service' 2>/dev/null || true
    systemctl --user disable --now 'hss-steam-trigger@*.service' 2>/dev/null || true

    for pf in /tmp/hss-steam-trigger-pids.txt /tmp/hss-steam-trigger-*-pids.txt; do
        [ -e "$pf" ] || continue
        xargs kill < "$pf" 2>/dev/null || true
        rm -f "$pf"
    done
    # The evtest listeners run as root, so the user systemd manager cannot kill
    # them via the service cgroup — terminate them explicitly per event node.
    for nf in /tmp/hss-steam-trigger-*-nodes.txt; do
        [ -e "$nf" ] || continue
        sudo -n /usr/local/sbin/hss-evtest-stop $(cat "$nf") 2>/dev/null || true
        rm -f "$nf"
    done
    rm -f /tmp/hss-steam-trigger-calibrating /tmp/xbox-steam-calibrating
    rm -f "$DEVICES_DIR"/*.conf
    rmdir "$DEVICES_DIR" 2>/dev/null || true
}

clear
if [ "$MODE" = "binds" ]; then
    banner_binds
else
    banner_uninstall
fi

if [ "$MODE" = "binds" ]; then
    count_binds

    if [ "$BIND_COUNT" -eq 0 ]; then
        echo -e "${GREEN}No binds found to remove.${CLEAR}"
        press_enter
        exit 0
    fi

    echo -e "${YELLOW}This will remove ${WHITE}${BIND_COUNT}${CLEAR} ${YELLOW}bound device(s).${CLEAR}"
    echo -e "  ${K_DIM}The program itself stays installed.${CLEAR}"
    echo ""

    if ! confirm "Remove all binds?"; then
        echo -e "${YELLOW}Aborted.${CLEAR}"
        exit 1
    fi

    echo -e "${YELLOW}Removing binds...${CLEAR}"
    remove_all_binds
    echo -e "${GREEN}Removed ${BIND_COUNT} binds successfully.${CLEAR}"
    press_enter
    exit 0
fi

# ---------------------------------------------------------------------------
# MODE = all — remove everything, including the Bind Manager itself
# ---------------------------------------------------------------------------

count_binds

echo -e "${YELLOW}This will remove:${CLEAR}"
echo -e "  - ${WHITE}${BIND_COUNT}${CLEAR} bound device(s) (hss-steam-trigger@<device>.service)"
echo -e "  - systemd template unit (hss-steam-trigger@.service)"
echo -e "  - sudoers rule (/etc/sudoers.d/hss-evtest)"
echo -e "  - evtest cleanup helper (/usr/local/sbin/hss-evtest-stop)"
echo -e "  - steam-trigger.sh ($APP_DIR/steam-trigger.sh)"
echo -e "  - config directory ($CONFIG_DIR)"
echo -e "  - Steam guide-button patches (restored to normal from backup)"
echo -e "  - the Bind Manager itself ($APP_DIR, $HSS_BIN)"
echo ""

if ! confirm "Uninstall hss?"; then
    echo -e "${YELLOW}Aborted.${CLEAR}"
    exit 1
fi

if pgrep -x steam >/dev/null 2>&1; then
    echo -e " ${YELLOW}Steam is running — its config files (config.vdf / localconfig.vdf) are restored from backup while Steam is closed.${CLEAR}"
    if confirm "Close Steam now?"; then
        echo -e " ${YELLOW}Closing Steam...${CLEAR}"
    else
        echo -e "${YELLOW}Uninstall aborted — Steam must be closed to restore the config.${CLEAR}"
        exit 1
    fi
fi

echo -e " ${YELLOW}Removing hyprland-steam-shortcut...${CLEAR}"

# Restore Steam's controller configuration (guide button, Xbox Configuration
# Support, per-game Steam Input) to its pre-fix state before removing the app.
# --force closes Steam if it is running. Never abort the uninstall over this.
if [ -x "$APP_DIR/steam-guide-btn-fix.sh" ]; then
    echo -e " ${YELLOW}Reverting Steam controller patches...${CLEAR}"
    # Align steam-guide-btn-fix.sh's own output (no leading space) with this
    # script's single-space message style by prefixing every line.
    revert_out=$("$APP_DIR/steam-guide-btn-fix.sh" revert --force 2>&1)
    revert_rc=$?
    printf '%s\n' "$revert_out" | sed 's/^/ /'
    if [ "$revert_rc" -ne 0 ]; then
        echo -e " ${YELLOW}Steam patch revert failed — continuing uninstall anyway.${CLEAR}"
    fi
fi

remove_all_binds

rm -f "$HOME/.config/systemd/user/hss-steam-trigger@.service"
rm -f "$HOME/.config/systemd/user/xbox-steam@.service"
rm -f "$HOME/.config/systemd/user/xbox-steam.service"
systemctl --user daemon-reload 2>/dev/null || true

rm -f "$HOME/steam_error.log"
rm -rf "$CONFIG_DIR"

sudo rm -f /etc/systemd/system/xbox-steam.service 2>/dev/null || true
sudo rm -f /etc/sudoers.d/hss-evtest 2>/dev/null || true
sudo rm -f /etc/sudoers.d/xbox-steam-evtest 2>/dev/null || true
sudo rm -f /usr/local/sbin/hss-evtest-stop 2>/dev/null || true

if [ "$BIND_COUNT" -eq 0 ]; then
    echo -e " ${GREEN}No binds found to remove. Uninstalled everything else successfully.${CLEAR}"
elif [ "$BIND_COUNT" -eq 1 ]; then
    echo -e " ${GREEN}Removed 1 bind and uninstalled successfully.${CLEAR}"
else
    echo -e " ${GREEN}Removed $BIND_COUNT binds and uninstalled successfully.${CLEAR}"
fi
echo -e " ${K_DIM}The 'hss' command and app files will be cleaned up automatically.${CLEAR}"

press_enter

# Remove the app directory + launcher synchronously, right before exit.
# A running bash keeps an open fd to its own script file, so deleting the
# directory here cannot break the remaining (builtin-only) work before exit.
# Doing it inline removes the background process entirely — no window where a
# pending cleanup could delete a freshly re-installed app directory (which
# previously surfaced as "uninstall.sh: No such file or directory").
rm -rf "$APP_DIR"
rm -f "$HSS_BIN"

exit 0
