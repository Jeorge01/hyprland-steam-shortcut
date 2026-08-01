#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Version (auto-detected from file modification date)
VERSION=$(date -r "$0" "+%Y-%m-%d" 2>/dev/null || echo "unknown")

HYPR_BLUE=$'\e[38;2;94;204;227m'
HYPR_DARK_BLUE=$'\e[38;2;85;184;204m'
HYPR_DARKEST_BLUE=$'\e[38;2;72;162;180m'

GREEN=$'\e[38;2;94;227;149m'
DARK_GREEN=$'\e[38;2;85;204;134m'
DARKEST_GREEN=$'\e[38;2;72;180;117m'

YELLOW=$'\e[38;2;244;208;63m'
RED=$'\e[38;2;231;76;60m'
BLUE=$'\e[38;2;52;152;219m'
CYAN=$'\e[38;2;26;188;156m'
WHITE=$'\e[1;37m'
GRAY_BG=$'\e[48;2;42;42;42m'
WHITE_FG=$'\e[38;2;255;255;255m'
RESET_ALL=$'\e[0m'
CLEAR=$'\e[0m'

K_DIM=$'\e[38;2;97;97;97m'
K_DIM2=$'\e[38;2;73;73;73m'
K_DIM3=$'\e[38;2;60;60;60m'

SEL_ARROW=$'\uf0da'

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/steam-shortcut"
DEVICES_DIR="$CONFIG_DIR/devices"
APP_DIR="$HOME/.local/share/hss"

log_info() {
    echo "$1" | fmt -w 57 | sed 's/^/   /'
}

run_cmd() {
    local output
    output=$("$@" 2>&1)
    if [ $? -ne 0 ]; then
        echo "$output" | fmt -w 54 | sed 's/^/      /'
        return 1
    fi
    return 0
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

confirm_dialog() {
    local prompt="$1" indent="${2:-0}"
    local sel=0 key rc=1 pad="" i
    local redbg=$'\e[48;2;231;76;60m'
    local graybg=$'\e[48;2;42;42;42m'
    local whitefg=$'\e[38;2;255;255;255m'
    local grayfg=$'\e[38;2;204;204;204m'
    for ((i = 0; i < indent; i++)); do pad+=" "; done

    render_buttons() {
        local yes no
        if [ "$sel" -eq 0 ]; then
            yes="${redbg}   ${CLEAR}${whitefg}${redbg} Yes ${CLEAR}${redbg}   ${CLEAR}"
            no="${graybg}   ${CLEAR}${grayfg}${graybg} No ${CLEAR}${graybg}   ${CLEAR}"
        else
            yes="${graybg}   ${CLEAR}${whitefg}${graybg} Yes ${CLEAR}${graybg}   ${CLEAR}"
            no="${redbg}   ${CLEAR}${whitefg}${redbg} No ${CLEAR}${redbg}   ${CLEAR}"
        fi
        printf '%s%s  %s\033[K\r\n' "$pad" "$yes" "$no" >/dev/tty
    }

    printf '\033[?25l' >/dev/tty
    printf '%s%s\033[K\r\n' "$pad" "${RED}${prompt}${CLEAR}" >/dev/tty
    echo "" >/dev/tty
    render_buttons
    echo "" >/dev/tty
    printf '%s%s\033[K\r\n' "$pad" "${K_DIM}←→${CLEAR} ${K_DIM2}toggle${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}enter${CLEAR} ${K_DIM2}submit${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}y${CLEAR} ${K_DIM2}Yes${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}n${CLEAR} ${K_DIM2}No${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}esc${CLEAR} ${K_DIM2}cancel${CLEAR}" >/dev/tty

    while IFS= read -r -s -n1 -t 0.001 _ </dev/tty; do :; done 2>/dev/null || true

    while :; do
        key=$(read_key)
        case "$key" in
            LEFT|RIGHT)
                sel=$((1 - sel))
                printf '\033[3A\033[K' >/dev/tty
                render_buttons
                printf '\033[2B' >/dev/tty
                ;;
            y|Y) rc=0; break ;;
            n|N) rc=1; break ;;
            enter) rc=$sel; break ;;
            ESC|q|Q) rc=1; break ;;
        esac
    done
    printf '\033[5A' >/dev/tty
    printf '\033[J' >/dev/tty
    printf '\033[?25h' >/dev/tty
    return "$rc"
}

# -------------------------------------------------------------------------
# HELPERS
# -------------------------------------------------------------------------

# Switches to the terminal's alternate screen buffer: while the program runs
# only it is visible, and anything written in the terminal before launch stays
# hidden but preserved (like vim/less). Leaving the buffer on exit restores
# the previous terminal content instead of deleting it.
alt_screen_on() {
    printf '\033[?1049h\033[H\033[2J' >/dev/tty 2>/dev/null || true
}
alt_screen_off() {
    printf '\033[?1049l' >/dev/tty 2>/dev/null || true
}

# Normalizes a per-instance identity (input Uniq or USB serial) into a safe
# systemd instance-name part: lowercase, alnum kept, runs of other chars -> '-'.
sanitize_id_part() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-\+//; s/-\+$//' | cut -c1-40
}

# USB iSerialNumber (if any) of the USB device owning an input event node,
# found by walking up the sysfs path from /sys/class/input/<event>. Empty when
# the event is not backed by a USB device or the device has no serial.
usb_serial_of_event() {
    local ev="$1" p s
    p=$(readlink -f "/sys/class/input/$ev" 2>/dev/null) || return 1
    while [ -n "$p" ] && [ "$p" != "/" ]; do
        if [ -f "$p/idVendor" ] && [ -f "$p/serial" ]; then
            s=$(cat "$p/serial" 2>/dev/null) || s=""
            if [ -n "$s" ]; then
                printf '%s\n' "$s"
                return 0
            fi
        fi
        p=${p%/*}
    done
    return 1
}

# The input U: Uniq value of the /proc record owning an event node (empty if none).
input_uniq_of_event() {
    local ev="$1"
    awk -v RS='' -v ev="$ev" '
        {
            hit = 0
            for (i = 1; i <= NF; i++) if ($i == "event" ev || $i == "Handlers=event" ev) hit = 1
            if (!hit) next
            p = index($0, "U: Uniq="); if (!p) next
            s = substr($0, p + 8); sub(/\n.*/, "", s)
            print s
        }' /proc/bus/input/devices 2>/dev/null
}

# Prints the event node numbers (eventN) currently matching the device.
# The device id may carry a per-instance suffix after the VID-PID pair
# (e.g. 045e-028e-<serial>) so two identical controllers get separate binds.
# Matching priority (Steam Input clones have empty Phys and are excluded):
#   id VID-PID-<instance>                    -> VID+PID and (input Uniq or USB
#                                                serial == instance)
#   id VID-PID + stored DEVICE_UNIQ          -> VID+PID + Uniq + non-empty Phys
#   id VID-PID + no uniq                     -> VID+PID + non-empty Phys
#   otherwise (e.g. e2e-test-controller)     -> exact Name match
device_events() {
    local id="$1" name="${2:-}" uniq="${3:-}" vid="" pid="" inst="" rest="" out="" ev="" kept=""
    if [[ "$id" =~ ^[0-9a-fA-F]{4}-[0-9a-fA-F]{4}(-[a-z0-9]+)*$ ]]; then
        vid=$(echo "${id%%-*}" | tr '[:upper:]' '[:lower:]')
        rest="${id#*-}"
        pid=$(echo "${rest%%-*}" | tr '[:upper:]' '[:lower:]')
        case "$rest" in
            *-*) inst="${rest#*-}" ;;
        esac
    fi
    if [ -n "$vid" ]; then
        if [ -n "$inst" ]; then
            out=$(awk -v RS='' -v vid="$vid" -v pid="$pid" '
                function physval(    s, p) {
                    p = index($0, "P: Phys="); if (!p) return ""
                    s = substr($0, p + 8); sub(/\n.*/, "", s); return s
                }
                index($0, "Vendor=" vid " ") && index($0, "Product=" pid " ") && physval() != "" {
                    for (i = 1; i <= NF; i++) if ($i ~ /^(Handlers=)?event[0-9]+$/) { sub(/^Handlers=/, "", $i); print $i }
                }' /proc/bus/input/devices 2>/dev/null)
            kept=""
            for ev in $out; do
                if [ "$(sanitize_id_part "$(input_uniq_of_event "$ev")")" = "$inst" ] || \
                   [ "$(sanitize_id_part "$(usb_serial_of_event "$ev")")" = "$inst" ]; then
                    [ -n "$kept" ] && kept+=$'\n'
                    kept+="$ev"
                fi
            done
            out="$kept"
        else
            if [ -n "$uniq" ]; then
                out=$(awk -v RS='' -v vid="$vid" -v pid="$pid" -v uniq="$uniq" '
                    function uniqval(    s, p) {
                        p = index($0, "U: Uniq="); if (!p) return ""
                        s = substr($0, p + 8); sub(/\n.*/, "", s); return s
                    }
                    function physval(    s, p) {
                        p = index($0, "P: Phys="); if (!p) return ""
                        s = substr($0, p + 8); sub(/\n.*/, "", s); return s
                    }
                    index($0, "Vendor=" vid " ") && index($0, "Product=" pid " ") && uniqval() == uniq && physval() != "" {
                        for (i = 1; i <= NF; i++) if ($i ~ /^(Handlers=)?event[0-9]+$/) { sub(/^Handlers=/, "", $i); print $i }
                    }' /proc/bus/input/devices 2>/dev/null)
            fi
            if [ -z "$out" ]; then
                out=$(awk -v RS='' -v vid="$vid" -v pid="$pid" '
                    function physval(    s, p) {
                        p = index($0, "P: Phys="); if (!p) return ""
                        s = substr($0, p + 8); sub(/\n.*/, "", s); return s
                    }
                    index($0, "Vendor=" vid " ") && index($0, "Product=" pid " ") && physval() != "" {
                        for (i = 1; i <= NF; i++) if ($i ~ /^(Handlers=)?event[0-9]+$/) { sub(/^Handlers=/, "", $i); print $i }
                    }' /proc/bus/input/devices 2>/dev/null)
            fi
        fi
    elif [ -n "$name" ]; then
        out=$(awk -v RS='' -v name="$name" '
            index($0, "N: Name=\"" name "\"") {
                for (i = 1; i <= NF; i++) if ($i ~ /^(Handlers=)?event[0-9]+$/) { sub(/^Handlers=/, "", $i); print $i }
            }' /proc/bus/input/devices 2>/dev/null)
    fi
    printf '%s\n' "$out"
}

device_owns_event() {
    local id="$1" name="$2" uniq="$3" ev="$4" list
    [ -z "$ev" ] && return 1
    list=$(device_events "$id" "$name" "$uniq")
    [ -z "$list" ] && return 1
    echo "$list" | grep -qw "$ev" && return 0
    return 1
}

bind_status() {
    local id="$1" conf="$2"
    local mode btn name state connected mod trg modc trgc btnc uniq
    mode=$(grep "^BIND_MODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
    if [ "$mode" = "combo" ]; then
        mod=$(grep "^MODIFIER_BTN_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
        trg=$(grep "^TRIGGER_BTN_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
        modc=$(grep "^MODIFIER_BTN_CODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
        trgc=$(grep "^TRIGGER_BTN_CODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
        btn="$mod ($modc) + $trg ($trgc)"
    else
        btn=$(grep "^TARGET_BTN_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
        btnc=$(grep "^TARGET_BTN_CODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
        btn="$btn ($btnc)"
    fi
    name=$(grep "^TARGET_DEV_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)

    if systemctl --user is-active --quiet "xbox-steam@$id.service" 2>/dev/null; then
        state_icon="${GREEN}●${CLEAR}"
        state_word="${GREEN}active  ${CLEAR}"
    else
        state_icon="${RED}●${CLEAR}"
        state_word="${RED}inactive${CLEAR}"
    fi

    uniq=$(grep "^DEVICE_UNIQ=" "$conf" 2>/dev/null | cut -d'"' -f2)
    if [ -n "$name" ] && device_events "$id" "$name" "$uniq" | grep -q .; then
        connected="${GREEN}connected${CLEAR}"
    else
        connected="${YELLOW}disconnected${CLEAR}"
    fi

    printf '%s %-8s  %s \u2022 %s \u2022 %s\n%12s%s %s' "$state_icon" "$state_word" "${WHITE}${name}${CLEAR}" "$id" "$connected" "" "$mode" "$btn"
}

bind_summary() {
    local id="$1" conf="$2" indent="${3:-0}"
    local mode btn name mod trg modc trgc btnc pad=""
    local i
    for ((i = 0; i < indent; i++)); do pad+=" "; done
    mode=$(grep "^BIND_MODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
    if [ "$mode" = "combo" ]; then
        mod=$(grep "^MODIFIER_BTN_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
        trg=$(grep "^TRIGGER_BTN_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
        modc=$(grep "^MODIFIER_BTN_CODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
        trgc=$(grep "^TRIGGER_BTN_CODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
        btn="$mod ($modc) + $trg ($trgc)"
    else
        btn=$(grep "^TARGET_BTN_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
        btnc=$(grep "^TARGET_BTN_CODE=" "$conf" 2>/dev/null | cut -d'"' -f2)
        btn="$btn ($btnc)"
    fi
    name=$(grep "^TARGET_DEV_NAME=" "$conf" 2>/dev/null | cut -d'"' -f2)
    printf '%s%s \u2022 %s\n%s%s %s' "$pad" "${WHITE}${name}${CLEAR}" "$id" "$pad" "$mode" "$btn"
}

restore_paused() {
    for u in "${PAUSED_UNITS[@]:-}"; do
        [ -n "$u" ] && systemctl --user start "$u" 2>/dev/null || true
    done
    if [ "${INPUT_REMAPPER_WAS_ACTIVE:-0}" -eq 1 ]; then
        sudo systemctl start input-remapper 2>/dev/null || true
    fi
}

# After a failure (e.g. device not connected): gum dialog where enter = back to
# the menu, or "Retry" to re-run calibration. Fallback: Enter prompt.
back_or_retry() {
    echo ""
    if command -v gum &>/dev/null; then
        if gum confirm "Return to the menu?" \
            --prompt.foreground "#E74C3C" \
            --selected.foreground "#FFFFFF" \
            --selected.background "#E74C3C" \
            --unselected.foreground "#CCCCCC" \
            --unselected.background "#2A2A2A" \
            --affirmative " Back " \
            --negative " Retry " \
            </dev/tty; then
            return 0
        else
            return 1
        fi
    else
        echo -e "   ${GRAY_BG}${WHITE_FG}Press Enter to return to the menu...${RESET_ALL}"
        read -r -s </dev/tty || true
        return 0
    fi
}

migrate_legacy() {
    [ -f "$CONFIG_DIR/config" ] || return 0
    grep -q '^TARGET_DEV_NAME=' "$CONFIG_DIR/config" || return 0
    if [ -d "$DEVICES_DIR" ] && ls "$DEVICES_DIR"/*.conf >/dev/null 2>&1; then
        return 0
    fi

    mkdir -p "$DEVICES_DIR"
    local old_name old_mode
    old_name=$(grep '^TARGET_DEV_NAME=' "$CONFIG_DIR/config" | cut -d'"' -f2)
    old_mode=$(grep '^BIND_MODE=' "$CONFIG_DIR/config" | cut -d'"' -f2)
    [ -z "$old_name" ] && return 0

    local rec vid product id uniq serial evnode
    rec=$(awk -v RS='' -v name="$old_name" 'for (i=1;i<=NF;i++) if ($i == "N: Name=\"" name "\"") { print; exit }' /proc/bus/input/devices)
    vid=$(echo "$rec" | grep -oP 'Vendor=\K[0-9A-Fa-f]{4}' | tr '[:upper:]' '[:lower:]')
    product=$(echo "$rec" | grep -oP 'Product=\K[0-9A-Fa-f]{4}' | tr '[:upper:]' '[:lower:]')
    uniq=$(echo "$rec" | grep -oP '^U: Uniq=\K.*' | head -n1)
    evnode=$(echo "$rec" | grep -oP '(Handlers=)?event[0-9]+' | head -n1 | sed 's/^Handlers=//')
    serial=$(usb_serial_of_event "$evnode" || true)
    if [ -n "$vid" ] && [ -n "$product" ]; then
        id="${vid}-${product}"
    else
        id=$(echo "$old_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//')
    fi

    cat > "$DEVICES_DIR/$id.conf" << EOFC
TARGET_DEV_NAME="$old_name"
DEVICE_UNIQ="$uniq"
DEVICE_SERIAL="$serial"
BIND_MODE="$old_mode"
TARGET_BTN_CODE=$(grep '^TARGET_BTN_CODE=' "$CONFIG_DIR/config" | cut -d'"' -f2)
TARGET_BTN_NAME=$(grep '^TARGET_BTN_NAME=' "$CONFIG_DIR/config" | cut -d'"' -f2)
MODIFIER_BTN_CODE=$(grep '^MODIFIER_BTN_CODE=' "$CONFIG_DIR/config" | cut -d'"' -f2)
MODIFIER_BTN_NAME=$(grep '^MODIFIER_BTN_NAME=' "$CONFIG_DIR/config" | cut -d'"' -f2)
TRIGGER_BTN_CODE=$(grep '^TRIGGER_BTN_CODE=' "$CONFIG_DIR/config" | cut -d'"' -f2)
TRIGGER_BTN_NAME=$(grep '^TRIGGER_BTN_NAME=' "$CONFIG_DIR/config" | cut -d'"' -f2)
EOFC

    cat > "$CONFIG_DIR/config" << EOFCFG
USER_NAME="${USER_NAME:-$(id -un)}"
USER_ID="${USER_ID:-$(id -u)}"
EOFCFG

    log_info "Migrated legacy single-bind config to device '$id'."

    if systemctl --user is-enabled xbox-steam.service 2>/dev/null || systemctl --user is-active xbox-steam.service 2>/dev/null; then
        systemctl --user enable "xbox-steam@$id.service" 2>/dev/null || true
    fi
    systemctl --user disable --now xbox-steam.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/xbox-steam.service"
}

toggle_bind() {
    local id="$1"
    if systemctl --user is-active --quiet "xbox-steam@$id.service" 2>/dev/null; then
        systemctl --user disable --now "xbox-steam@$id.service" 2>/dev/null || true
    else
        systemctl --user enable --now "xbox-steam@$id.service" 2>/dev/null || true
    fi
}

read_key() {
    local key extra extra2
    local read_args=(-r -s -n1)
    if [ -n "${1:-}" ]; then
        read_args+=(-t "$1")
    fi
    if ! IFS= read "${read_args[@]}" key </dev/tty; then
        echo "TIMEOUT"
        return 0
    fi
    if [ "$key" = $'\e' ]; then
        if IFS= read -r -s -n1 -t 0.1 extra </dev/tty; then
            if [ "$extra" = "[" ]; then
                IFS= read -r -s -n1 -t 0.1 extra2 </dev/tty
                case "$extra2" in
                    A) echo "UP" ;;
                    B) echo "DOWN" ;;
                    C) echo "RIGHT" ;;
                    D) echo "LEFT" ;;
                    *) echo "ESC" ;;
                esac
            else
                echo "ESC"
            fi
        else
            echo "ESC"
        fi
    elif [ -z "$key" ] || [ "$key" = $'\r' ] || [ "$key" = $'\n' ]; then
        echo "enter"
    else
        echo "$key"
    fi
}

drain_keys() {
    while IFS= read -r -s -n1 -t 0.05 _ </dev/tty 2>/dev/null; do :; done
}

blue_line() {
    local esc=$'\e'
    if printf '%s' "$1" | grep -q "${esc}\\[1;37m"; then
        printf '%s' "$1" | sed "s/${esc}\\[1;37m/${HYPR_BLUE}/g"
    else
        printf '%s%s%s' "$HYPR_BLUE" "$1" "$CLEAR"
    fi
}

device_menu() {
    local -a it=("$@")
    local count=${#it[@]}
    local sel=0 last_sel=-1
    local key res=""

    printf '\033[?25l' >/dev/tty
    printf '\033[H\033[J' >/dev/tty

    render() {
        local i first line selected repaint=0
        if [ "$sel" -ne "$last_sel" ]; then
            repaint=1
        fi
        if [ -n "${REFRESH_CB:-}" ]; then
            local -a saved
            saved=("${it[@]}")
            "$REFRESH_CB" it
            count=${#it[@]}
            if [ "${#it[@]}" -ne "${#saved[@]}" ]; then
                repaint=1
            else
                for i in "${!it[@]}"; do
                    [ "${it[$i]}" != "${saved[$i]}" ] && repaint=1
                done
            fi
        fi
        last_sel="$sel"
        [ "$repaint" -eq 0 ] && return 0
        printf '\033[H' >/dev/tty
        banner_bound_devices >/dev/tty
        for i in "${!it[@]}"; do
            if [ "$i" -eq $((count - 1)) ]; then
                echo "" >/dev/tty
            fi
            if [ "$i" -eq "$sel" ]; then
                selected=1
            else
                selected=0
            fi
            first=1
            while IFS= read -r line; do
                if [ "$first" -eq 1 ]; then
                    if [ "$selected" -eq 1 ]; then
                        echo -e "${HYPR_BLUE}${SEL_ARROW}${CLEAR} $(blue_line "$line")\033[K" >/dev/tty
                    else
                        echo -e "  ${line}\033[K" >/dev/tty
                    fi
                    first=0
                else
                    echo -e "  ${line}\033[K" >/dev/tty
                fi
            done <<< "${it[$i]}"
        done
        echo "" >/dev/tty
        echo -e "  ${K_DIM}←↓↑→${CLEAR} ${K_DIM2}navigate${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}enter${CLEAR} ${K_DIM2}submit${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}t${CLEAR} ${K_DIM2}toggle${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}r${CLEAR} ${K_DIM2}rebind${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}d${CLEAR} ${K_DIM2}remove${CLEAR}" >/dev/tty
        printf '\033[J' >/dev/tty
    }

    render

    while IFS= read -r -s -n1 -t 0.001 _ </dev/tty; do :; done 2>/dev/null || true

    while [ -z "$res" ]; do
        key=$(read_key 0.5)
        case "$key" in
            TIMEOUT)
                ;;
            UP)
                [ "$sel" -gt 0 ] && sel=$((sel - 1))
                ;;
            DOWN)
                [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1))
                ;;
            enter)
                [ "$sel" -eq $((count - 1)) ] && res="BACK"
                ;;
            t)
                if [ "$sel" -lt $((count - 1)) ]; then
                    if [ -n "${TOGGLE_CB:-}" ]; then
                        local new_item
                        new_item="$("$TOGGLE_CB" "$sel")"
                        if [ -n "$new_item" ] && [ -z "${REFRESH_CB:-}" ]; then
                            it[$sel]="$new_item"
                        fi
                        drain_keys
                        render
                    else
                        res="TOGGLE:$sel"
                    fi
                fi
                ;;
            r)
                if [ "$sel" -lt $((count - 1)) ]; then
                    res="REBIND:$sel"
                fi
                ;;
            d)
                if [ "$sel" -lt $((count - 1)) ]; then
                    res="DELETE:$sel"
                fi
                ;;
            ESC)
                res="BACK"
                ;;
        esac
        if [ -z "$res" ]; then
            render
        else
            drain_keys
        fi
    done

    printf '\033[?25h' >/dev/tty
    echo "$res"
}

no_binds_view() {
    local removed="${1:-}"
    printf '\033[?25l' >/dev/tty
    clear
    banner_bound_devices
    if [ -n "$removed" ]; then
        echo -e "${GREEN}Bind removed.${CLEAR}"
        echo ""
    fi
    echo -e "${YELLOW}  You have no bound devices. Use 'Bind device' in the main menu to add one.${CLEAR}"
    echo ""
    echo -e "  ${K_DIM}enter${CLEAR} ${K_DIM2}back${CLEAR}"
    read -r -s -n1 </dev/tty || true
    printf '\033[?25h' >/dev/tty
    return 0
}

manage_binds() {
    migrate_legacy

    local confs=()
    while IFS= read -r f; do
        confs+=("$f")
    done < <(ls "$DEVICES_DIR"/*.conf 2>/dev/null | sort)

    if [ ${#confs[@]} -eq 0 ]; then
        no_binds_view
        return 0
    fi

    local TOGGLE_CB=toggle_menu_item
    toggle_menu_item() {
        local idx="$1"
        local id="${ids[$idx]}"
        toggle_bind "$id"
        bind_status "$id" "$DEVICES_DIR/$id.conf"
    }

    # Live-refresh of the bound devices list: called on an idle timer so
    # connected/disconnected (and active/inactive) updates without leaving the
    # menu. Only repaints when something actually changed.
    local REFRESH_CB=refresh_menu_items
    refresh_menu_items() {
        local -n items_ref="$1"
        local -a new_items=()
        local conf id
        for conf in "${confs[@]}"; do
            id=$(basename "$conf" .conf)
            new_items+=("$(bind_status "$id" "$conf")")
        done
        new_items+=("⟵ Back")
        items_ref=("${new_items[@]}")
    }

    while true; do
        local items=() ids=() row id conf i
        for conf in "${confs[@]}"; do
            id=$(basename "$conf" .conf)
            items+=("$(bind_status "$id" "$conf")")
            ids+=("$id")
        done

        local choice
        choice=$(device_menu "${items[@]}" "⟵ Back")

        case "$choice" in
            "BACK")
                return 0
                ;;
            "TOGGLE:"*)
                toggle_bind "${ids[${choice#TOGGLE:}]}"
                ;;
            "REBIND:"*)
                echo ""
                bind_flow --device "${ids[${choice#REBIND:}]}"
                ;;
            "DELETE:"*)
                local aid="${ids[${choice#DELETE:}]}"
                clear
                echo ""
                bind_summary "$aid" "$DEVICES_DIR/$aid.conf" 2
                echo ""
                echo ""
                if confirm_dialog "Remove this bind?" 2; then
                    systemctl --user disable --now "xbox-steam@$aid.service" 2>/dev/null || true
                    rm -f "$DEVICES_DIR/$aid.conf"
                    confs=()
                    while IFS= read -r f; do
                        confs+=("$f")
                    done < <(ls "$DEVICES_DIR"/*.conf 2>/dev/null | sort)
                    if [ ${#confs[@]} -eq 0 ]; then
                        no_binds_view removed
                        return 0
                    else
                        echo -e "${GREEN}Bind removed.${CLEAR}"
                    fi
                fi
                ;;
            *)
                return 0
                ;;
        esac
    done
}

# -------------------------------------------------------------------------
# ASCII ART BANNERS
# -------------------------------------------------------------------------

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

banner_calibration() {
    echo -e "${HYPR_BLUE}"

    art_line "▄▖  ▜ ▘▌     ▗ ▘" 7 15
    art_line "▌ ▀▌▐ ▌▛▌▛▘▀▌▜▘▌▛▌▛▌" 7 15
    art_line "▙▖█▌▐▖▌▙▌▌ █▌▐▖▌▙▌▌▌" 7 15
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "${HYPR_BLUE}" "Cr" "${HYPR_DARK_BLUE}" "ea" "${HYPR_DARKEST_BLUE}" "te" "${HYPR_BLUE}" " yo" "${HYPR_DARK_BLUE}" "ur" "${HYPR_BLUE}" " bi" "${HYPR_DARK_BLUE}" "nd" "${CLEAR}"
    echo ""
}

banner_bound_devices() {
    echo -e "${HYPR_BLUE}"

    art_line "▄        ▌  ▄     ▘" 4 8 12 18 21
    art_line "▙▘▛▌▌▌▛▌▛▌  ▌▌█▌▌▌▌▛▘█▌▛▘" 4 8 12 18 21
    art_line "▙▘▙▌▙▌▌▌▙▌  ▙▘▙▖▚▘▌▙▖▙▖▄▌" 4 8 12 18 21
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "${HYPR_BLUE}" "Ma" "${HYPR_DARK_BLUE}" "na" "${HYPR_DARKEST_BLUE}" "ge" "${HYPR_BLUE}" " yo" "${HYPR_DARK_BLUE}" "ur" "${HYPR_BLUE}" " bi" "${HYPR_DARK_BLUE}" "nd" "${HYPR_DARKEST_BLUE}" "s" "${CLEAR}"
    echo ""
}

banner_options() {
    echo -e "${HYPR_BLUE}"

    art_line "▄▖  ▗ ▘      " 6 9
    art_line "▌▌▛▌▜▘▌▛▌▛▌▛▘" 6 9
    art_line "▙▌▙▌▐▖▌▙▌▌▌▄▌" 6 9
    printf '  %s%s%s%s%s%s%s\n' "${HYPR_BLUE}" "▌ " "${HYPR_BLUE}" "Me" "${HYPR_DARK_BLUE}" "nu" "${CLEAR}"
    echo ""
}

show_banner() {
    echo -e "${HYPR_BLUE}"

    art_line "▖▖      ▜      ▌  ▄▖▗          ▄▖▌     ▗     ▗ " 6 12 18 22 26 31 37 43
    art_line "▙▌▌▌▛▌▛▘▐ ▀▌▛▌▛▌  ▚ ▜▘█▌▀▌▛▛▌  ▚ ▛▌▛▌▛▘▜▘▛▘▌▌▜▘" 6 12 18 22 26 31 37 43
    art_line "▌▌▙▌▙▌▌ ▐▖█▌▌▌▙▌  ▄▌▐▖▙▖█▌▌▌▌  ▄▌▌▌▙▌▌ ▐▖▙▖▙▌▐▖" 6 12 18 22 26 31 37 43
    printf '  %s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "${HYPR_BLUE}" "▄▌▌  " "${HYPR_BLUE}" "Bi" "${HYPR_DARK_BLUE}" "n" "${HYPR_DARKEST_BLUE}" "d" "${HYPR_BLUE}" " ma" "${HYPR_DARK_BLUE}" "na" "${HYPR_DARKEST_BLUE}" "ger" "${CLEAR}"
}

# Interactive runs switch to the alternate screen buffer — the terminal's
# previous content is hidden while the program runs and restored on exit.
# --version/--status keep their output intact.
if [ "${1:-}" != "--version" ] && [ "${1:-}" != "--status" ]; then
    alt_screen_on
fi

show_banner

# Handle --version flag
if [ "${1:-}" = "--version" ]; then
    echo "Latest update: ${VERSION}"
    exit 0
fi

# Handle --status flag
if [ "${1:-}" = "--status" ]; then
    echo -e "    Version:    ${WHITE}${VERSION}${CLEAR}"

    if [ -d "$DEVICES_DIR" ]; then
        found=0
        for conf in "$DEVICES_DIR"/*.conf; do
            [ -e "$conf" ] || continue
            found=1
            id=$(basename "$conf" .conf)
            row=$(bind_status "$id" "$conf")
            first=1
            while IFS= read -r line; do
                if [ "$first" -eq 1 ]; then
                    echo -e "    ${WHITE}•${CLEAR} $line"
                    first=0
                else
                    echo -e "      $line"
                fi
            done <<< "$row"
        done
        if [ "$found" -eq 0 ]; then
            echo -e "    ${YELLOW}No binds found.${CLEAR}"
        fi
    else
        echo -e "    ${YELLOW}No installation found.${CLEAR}"
    fi

    if [ -f "$CONFIG_DIR/config" ] && grep -q '^TARGET_DEV_NAME=' "$CONFIG_DIR/config"; then
        echo -e "    ${YELLOW}Legacy config detected — run the installer to migrate.${CLEAR}"
    fi

    exit 0
fi

sudo -v </dev/tty || exit 1
while true; do sudo -n true; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!

cleanup() {
    printf '\033[?25h' >/dev/tty 2>/dev/null || true
    stty echo </dev/tty 2>/dev/null || true

    if [ -f /tmp/xbox-steam-calibrating ]; then
        rm -f /tmp/xbox-steam-calibrating
        echo ""
        echo -e "${YELLOW}Calibration aborted. Restoring previous binds...${CLEAR}"
        restore_paused
        echo -e "${GREEN}Previous binds restored.${CLEAR}"
    fi

    kill $(jobs -p) 2>/dev/null || true
    kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true

    # Interactive runs restore the terminal's previous content on exit.
    if [ "${HSS_INTERACTIVE:-0}" -eq 1 ]; then
        alt_screen_off
    fi
}

trap cleanup EXIT

# -------------------------------------------------------------------------
# STEP 1: PRE-FLIGHT CHECKS & DISTRO DETECTION (FAIL-FAST)
# -------------------------------------------------------------------------

if [ "$(id -u)" = "0" ]; then
    echo -e "${YELLOW}⚠️ Do not run this script with 'sudo' or as root directly.${CLEAR}"
    echo -e "${YELLOW}   Run it as a regular user. The script will ask for sudo when needed.${CLEAR}"
    exit 1
fi

# Batch validation: system requirements
ERRORS=()

if ! command -v systemctl &> /dev/null; then
    ERRORS+=("systemd (systemctl) not found — required for systemd user service")
fi

if command -v pacman &> /dev/null; then
    DISTRO="󰣇 Arch"
    PKG_MANAGER="pacman"
elif command -v dnf &> /dev/null; then
    DISTRO=" Fedora"
    PKG_MANAGER="dnf"
else
    ERRORS+=("Unsupported distribution — endast Arch (pacman) och Fedora (dnf)")
fi

if ! command -v hyprctl &> /dev/null; then
    ERRORS+=("Hyprland (hyprctl) not found — required for workspace focus")
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}❌ Installation cannot continue:${CLEAR}"
    for err in "${ERRORS[@]}"; do
        echo -e "${RED}   • ${err}${CLEAR}"
    done
    exit 1
fi

if ! command -v steam &> /dev/null; then
    echo -e "${RED}❌ ERROR: Steam is missing from your system.${CLEAR}"
    echo -e "${RED}   Please install Steam first before running this installation script.${CLEAR}"
    exit 1
fi

USER_NAME=$(id -un)
USER_ID=$(id -u)

# -------------------------------------------------------------------------
# CALIBRATION
# -------------------------------------------------------------------------

# Monitors for input devices that appear after calibration has started and
# spawns evtest on them. This makes it irrelevant when the controller is turned
# on relative to when evtest was started — a device switched on during the
# confirmation dialog (or while waiting for input) is still caught.
# KNOWN: space-separated list of event nodes already being monitored.
# FILTER_ID: if set, only attach to nodes belonging to that device (id, name, uniq).
# Runs in the background until calibration finishes (killed by "kill $(jobs -p)").
spawn_hotplug_evtest() {
    local known="$1" filter_id="$2" filter_name="$3" filter_uniq="$4" ev
    trap 'kill $(jobs -p) 2>/dev/null || true; exit 0' TERM INT
    while :; do
        sleep 0.2
        for ev in /dev/input/event*; do
            [ -e "$ev" ] || continue
            case " $known " in
                *" $ev "*) continue ;;
            esac
            if [ -z "$filter_id" ] || device_owns_event "$filter_id" "$filter_name" "$filter_uniq" "${ev##*/}"; then
                sudo stdbuf -oL timeout 130 evtest "$ev" 2>/dev/null | stdbuf -oL sed "s|^|$ev: |" >> "$CALIB_EVTEST" &
            fi
            known="$known $ev"
        done
    done
}

# Spawns evtest for all (or the given) devices. Runs before the confirmation
# dialog so the evtest startup is hidden behind it — a button press right after
# "Calibrate" is then caught without delay. A hotplug watcher keeps attaching
# evtest to devices that are turned on after this point.
# Sets CALIB_EVTEST (temp file) and DEV_COUNT (number of spawned devices).
# Returns 1 if a given device is not connected.
spawn_calib_evtest() {
    CALIB_EVTEST=$(mktemp)
    DEV_COUNT=0
    CALIB_MONITORED=""
    if [ -n "$FIXED_DEVICE_ID" ]; then
        FIXED_NAME=$(grep "^TARGET_DEV_NAME=" "$DEVICES_DIR/$FIXED_DEVICE_ID.conf" 2>/dev/null | cut -d'"' -f2)
        [ -z "$FIXED_NAME" ] && FIXED_NAME="$FIXED_DEVICE_ID"
        FIXED_UNIQ=$(grep "^DEVICE_UNIQ=" "$DEVICES_DIR/$FIXED_DEVICE_ID.conf" 2>/dev/null | cut -d'"' -f2)
        FIXED_EVENTS=$(device_events "$FIXED_DEVICE_ID" "$FIXED_NAME" "$FIXED_UNIQ")
        if [ -z "$FIXED_EVENTS" ]; then
            echo ""
            echo -e "${RED}❌ ERROR: Device '$FIXED_NAME' is not connected.${CLEAR}"
            echo -e "${RED}   Connect the device and try rebinding again.${CLEAR}"
            return 1
        fi
        for evnode in $FIXED_EVENTS; do
            if [ -e "/dev/input/$evnode" ]; then
                sudo stdbuf -oL timeout 130 evtest "/dev/input/$evnode" 2>/dev/null | stdbuf -oL sed "s|^|/dev/input/$evnode: |" >> "$CALIB_EVTEST" &
                DEV_COUNT=$((DEV_COUNT + 1))
                CALIB_MONITORED="$CALIB_MONITORED /dev/input/$evnode"
            fi
        done
        spawn_hotplug_evtest "$CALIB_MONITORED" "$FIXED_DEVICE_ID" "$FIXED_NAME" "$FIXED_UNIQ" &
    else
        for ev in /dev/input/event*; do
            if [ -r "$ev" ] || [ "$(id -u)" = "0" ] || command -v sudo &>/dev/null; then
                sudo stdbuf -oL timeout 130 evtest "$ev" 2>/dev/null | stdbuf -oL sed "s|^|$ev: |" >> "$CALIB_EVTEST" &
                DEV_COUNT=$((DEV_COUNT + 1))
                CALIB_MONITORED="$CALIB_MONITORED $ev"
            fi
        done
        spawn_hotplug_evtest "$CALIB_MONITORED" "" "" "" &
    fi
    return 0
}

calibrate() {
IS_REDO=0
# On a retry from bind_flow (e.g. device not connected) the confirmation dialog
# is skipped — the READY banner/introduction is already part of the header.
[ "${CALIB_RETRY:-0}" -eq 1 ] && IS_REDO=1
while true; do
if [ "${IS_REDO:-0}" -eq 0 ]; then
set +e
if ! spawn_calib_evtest; then
    set -e
    return 1
fi
echo ""
if command -v gum &>/dev/null; then
    if ! gum confirm "Ready to calibrate?" \
        --affirmative " Calibrate " \
        --negative " Cancel " \
        --prompt.foreground "#5ECCDF" \
        --selected.foreground "#FFFFFF" \
        --selected.background "#5ECCDF" \
        --unselected.foreground "#CCCCCC" \
        --unselected.background "#2A2A2A" \
        </dev/tty; then
        echo -e "${YELLOW}   Aborted.${CLEAR}"
        kill $(jobs -p) 2>/dev/null || true
        rm -f "$CALIB_EVTEST"
        set -e
        return 2
    fi
else
    echo -n "Ready to calibrate? (y/n): "
    read -r r </dev/tty
    if [[ ! "$r" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}   Aborted.${CLEAR}"
        kill $(jobs -p) 2>/dev/null || true
        rm -f "$CALIB_EVTEST"
        set -e
        return 2
    fi
fi
echo ""
else
echo ""
echo ""
set +e
if ! spawn_calib_evtest; then
    set -e
    return 1
fi
fi

# Wait until all evtest processes have opened their devices (max 3s). On the
# first run the startup is already hidden behind the confirmation dialog —
# this covers the redo path which has no dialog.
W=0
while [ "$W" -lt 30 ]; do
    N=$(grep -c "Input device ID:" "$CALIB_EVTEST" 2>/dev/null || true)
    [ -z "$N" ] && N=0
    [ "$N" -ge "$DEV_COUNT" ] && break
    sleep 0.1
    W=$((W + 1))
done

# Discard events recorded before confirmation (dialog keys etc.)
: > "$CALIB_EVTEST"


printf '\033[?25l' >/dev/tty
stty -echo </dev/tty 2>/dev/null || true
echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')Waiting for input...$(printf '%*s' 21 '')${RESET_ALL}  ${K_DIM}esc${CLEAR} ${K_DIM2}abort${CLEAR}"

(
    while :; do
        if IFS= read -r -s -n1 -t 0.1 k </dev/tty 2>/dev/null; then
            if [ "$k" = $'\e' ]; then
                if IFS= read -r -s -n1 -t 0.02 extra </dev/tty 2>/dev/null; then
                    if [ "$extra" != "[" ]; then
                        touch /tmp/xbox-steam-calib-esc
                        exit 0
                    fi
                else
                    touch /tmp/xbox-steam-calib-esc
                    exit 0
                fi
            fi
        fi
    done
) &
CALIB_ESC_PID=$!

CALIB_PHASE=1
CAPTURED_LINE=""
COMBO_RESULT=""
COMBO_BTN_CODE=""
COMBO_BTN_NAME=""

CALIB_ABORTED=0
while :; do
    if [ -f /tmp/xbox-steam-calib-esc ]; then
        CALIB_ABORTED=1
        break
    fi
    if IFS= read -r -t 0.1 line; then
        :
    else
        read_rc=$?
        if [ "$read_rc" -gt 128 ]; then
            continue
        fi
        break
    fi
    if [ "$CALIB_PHASE" -eq 1 ]; then
        if echo "$line" | grep -q "code.*BTN_.*value 1"; then
            CAPTURED_LINE="$line"
            DETECTED_EV=$(echo "$line" | awk -F':' '{print $1}')
            FIRST_BTN_CODE=$(echo "$line" | grep -oP 'code \K[0-9]+')
            FIRST_BTN_NAME=$(echo "$line" | grep -oP 'BTN_[A-Z0-9]+')

            DEV_RECORD=$(awk -v RS='' '/Handlers=.*'"${DETECTED_EV##*/}"'( |$)/' /proc/bus/input/devices)
            TARGET_DEV_NAME=$(echo "$DEV_RECORD" | grep -oP 'Name="\K[^"]+')
            [ -z "$TARGET_DEV_NAME" ] && TARGET_DEV_NAME="Generic Controller"
            DEVICE_UNIQ=$(echo "$DEV_RECORD" | grep -oP '^U: Uniq=\K.*' | head -n1)
            DEVICE_SERIAL=$(usb_serial_of_event "${DETECTED_EV##*/}" || true)

            VENDOR=$(echo "$DEV_RECORD" | grep -oP 'Vendor=\K[0-9A-Fa-f]{4}' | tr '[:upper:]' '[:lower:]')
            PRODUCT=$(echo "$DEV_RECORD" | grep -oP 'Product=\K[0-9A-Fa-f]{4}' | tr '[:upper:]' '[:lower:]')
            if [ -n "$VENDOR" ] && [ -n "$PRODUCT" ]; then
                DEVICE_ID="${VENDOR}-${PRODUCT}"
                if [ -n "$DEVICE_UNIQ" ]; then
                    DEVICE_INSTANCE=$(sanitize_id_part "$DEVICE_UNIQ")
                else
                    DEVICE_INSTANCE=$(sanitize_id_part "$DEVICE_SERIAL")
                fi
                if [ -n "$DEVICE_INSTANCE" ]; then
                    DEVICE_ID="${DEVICE_ID}-${DEVICE_INSTANCE}"
                fi
            else
                DEVICE_ID=$(echo "$TARGET_DEV_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//')
            fi
            if [ -n "$FIXED_DEVICE_ID" ]; then
                DEVICE_ID="$FIXED_DEVICE_ID"
            fi

            echo -ne "\033[1A\033[2K\r"
            echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')Detected: ${FIRST_BTN_NAME}$(printf '%*s' $((31 - ${#FIRST_BTN_NAME})) '')${RESET_ALL}"
            echo ""
            echo -e -n "  Hold for ${YELLOW}combo${CLEAR}, or release for ${HYPR_BLUE}single${CLEAR} mode...   ${K_DIM}esc${CLEAR} ${K_DIM2}abort${CLEAR}"
            CALIB_PHASE=2
        fi
    else
        if [[ "$line" != "${DETECTED_EV}:"* ]]; then
            continue
        fi
        if echo "$line" | grep -q "code $FIRST_BTN_CODE .*value 0"; then
            COMBO_RESULT="single"
            break
        fi
        if echo "$line" | grep -q "code.*BTN_.*value 1"; then
            BTN_CODE=$(echo "$line" | grep -oP 'code \K[0-9]+')
            if [ "$BTN_CODE" != "$FIRST_BTN_CODE" ]; then
                COMBO_RESULT="combo"
                COMBO_BTN_CODE="$BTN_CODE"
                COMBO_BTN_NAME=$(echo "$line" | grep -oP 'BTN_[A-Z0-9]+')
            else
                COMBO_RESULT="single"
            fi
            break
        fi
    fi
done < <(timeout 70 tail -f -n +1 "$CALIB_EVTEST" 2>/dev/null)
printf '\033[?25h' >/dev/tty
stty echo </dev/tty 2>/dev/null || true
set -e

CALIB_ESC_HELD=0
[ -f /tmp/xbox-steam-calib-esc ] && CALIB_ESC_HELD=1
kill "$CALIB_ESC_PID" 2>/dev/null || true
rm -f /tmp/xbox-steam-calib-esc
[[ -n "$(jobs -p)" ]] && kill $(jobs -p) 2>/dev/null || true
rm -f "$CALIB_EVTEST"

if [ "$CALIB_ABORTED" -eq 1 ] || [ "$CALIB_ESC_HELD" -eq 1 ]; then
    echo -ne "\033[1A\033[2K\r"
    echo -e "${YELLOW}Calibration aborted.${CLEAR}"
    echo ""
    return 2
fi

if [ -z "$CAPTURED_LINE" ]; then
    echo -ne "\033[1A\033[2K\r"
    echo -e "${RED}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"
    echo -ne "\033[2K\r"
    echo -e "${RED}│${CLEAR} ❌ ERROR: No input device activity detected within 60s.         ${RED}│${CLEAR}"
    echo -ne "\033[2K\r"
    echo -e "${RED}│${CLEAR}    Installation aborted. Please try again.                      ${RED}│${CLEAR}"
    echo -ne "\033[2K\r"
    echo -e "${RED}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
    echo -e ""
    echo -e "   ${YELLOW}Checking for conflicting processes...${CLEAR}"
    echo -e ""

    CONFLICT_FOUND=0
    if systemctl is-active --quiet input-remapper 2>/dev/null; then
        echo -e "   ${RED}●${CLEAR} input-remapper is running — ${YELLOW}sudo systemctl stop input-remapper${CLEAR}"
        CONFLICT_FOUND=1
    fi
    if pgrep -x "hkdm" > /dev/null 2>&1; then
        echo -e "   ${RED}●${CLEAR} hkdm is running — ${YELLOW}sudo pacman -R hkdm${CLEAR}"
        CONFLICT_FOUND=1
    fi

    HELD_BY=$(sudo fuser /dev/input/event* 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i+0==$i) print $i}' | sort -u)
    if [ -n "$HELD_BY" ]; then
        for PID in $HELD_BY; do
            PROC_NAME=$(cat /proc/$PID/comm 2>/dev/null || echo "unknown")
            echo -e "   ${RED}●${CLEAR} /dev/input/event* held by PID $PID ($PROC_NAME) — ${YELLOW}sudo kill -9 $PID${CLEAR}"
        done
        CONFLICT_FOUND=1
    fi

    if [ "$CONFLICT_FOUND" -eq 0 ]; then
        echo -e "   ${YELLOW}No obvious conflicts found.${CLEAR}"
        echo -e "   Make sure your controller is ${GREEN}ON${CLEAR} and ${GREEN}connected${CLEAR}."
    fi

    echo -e ""
    return 1
fi

COMBO_FOUND=0

if [ "$COMBO_RESULT" = "combo" ]; then
    COMBO_FOUND=1
    BIND_MODE="combo"
    MODIFIER_BTN_CODE="$FIRST_BTN_CODE"
    MODIFIER_BTN_NAME="$FIRST_BTN_NAME"
    TRIGGER_BTN_CODE="$COMBO_BTN_CODE"
    TRIGGER_BTN_NAME="$COMBO_BTN_NAME"
else
    COMBO_FOUND=0
fi

if [ "$COMBO_FOUND" -eq 0 ]; then
    BIND_MODE="single"
    TARGET_BTN_CODE="$FIRST_BTN_CODE"
    TARGET_BTN_NAME="$FIRST_BTN_NAME"
fi

if [ "$BIND_MODE" = "combo" ]; then
    BIND_LABEL="${MODIFIER_BTN_NAME} (${MODIFIER_BTN_CODE}) + ${TRIGGER_BTN_NAME} (${TRIGGER_BTN_CODE})"
else
    BIND_LABEL="${TARGET_BTN_NAME} (${TARGET_BTN_CODE})"
fi

echo -ne "\033[2A\033[2K\r"
echo -e "${GRAY_BG}${WHITE_FG}$(printf '%*s' 22 '')${BIND_LABEL}$(printf '%*s' $((41 - ${#BIND_LABEL})) '')${RESET_ALL}"
echo -ne "\033[2K\r"
echo -ne "\033[2K\r"

echo ""
echo -e "${HYPR_BLUE}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"

VAL_COL=21

if [ "$BIND_MODE" = "combo" ]; then
    L3_VAL="${MODIFIER_BTN_NAME} (${MODIFIER_BTN_CODE}) + ${TRIGGER_BTN_NAME} (${TRIGGER_BTN_CODE})"
else
    L3_VAL="${TARGET_BTN_NAME} (Code: ${TARGET_BTN_CODE})"
fi

L2_TRAIL=$(printf '%*s' $((59 - VAL_COL - ${#TARGET_DEV_NAME})) '')
L3_TRAIL=$(printf '%*s' $((59 - VAL_COL - ${#L3_VAL})) '')
L4_TRAIL=$(printf '%*s' $((59 - VAL_COL - ${#BIND_MODE})) '')

COLOR_L1="${HYPR_BLUE}   Bu${HYPR_DARK_BLUE}tt${HYPR_DARKEST_BLUE}on${HYPR_BLUE} pr${HYPR_DARK_BLUE}es${HYPR_DARKEST_BLUE}s${HYPR_BLUE} det${HYPR_DARK_BLUE}ect${HYPR_DARKEST_BLUE}ed!${CLEAR}   $(printf '%*s' $((59 - 25)) '')"
COLOR_L2="${HYPR_BLUE}   Det${HYPR_DARK_BLUE}ect${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} De${HYPR_DARK_BLUE}vi${HYPR_DARKEST_BLUE}ce${HYPR_BLUE}:     ${CLEAR}${WHITE}${TARGET_DEV_NAME}${CLEAR}${L2_TRAIL}"
if [ "$BIND_MODE" = "combo" ]; then
    COLOR_L3="${HYPR_BLUE} 󰪥  Ma${HYPR_DARK_BLUE}pp${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} Co${HYPR_DARK_BLUE}mb${HYPR_DARKEST_BLUE}o${HYPR_BLUE}:        ${CLEAR}${WHITE}${L3_VAL}${CLEAR}${L3_TRAIL}"
else
    COLOR_L3="${HYPR_BLUE} 󰪥  Ma${HYPR_DARK_BLUE}pp${HYPR_DARKEST_BLUE}ed${HYPR_BLUE} Bu${HYPR_DARK_BLUE}tt${HYPR_DARKEST_BLUE}on${HYPR_BLUE}:       ${CLEAR}${WHITE}${L3_VAL}${CLEAR}${L3_TRAIL}"
fi
COLOR_L4="${HYPR_BLUE}   Bi${HYPR_DARK_BLUE}nd${HYPR_DARKEST_BLUE} T${HYPR_BLUE}yp${HYPR_DARK_BLUE}e${HYPR_DARKEST_BLUE}:${CLEAR}           ${WHITE}${BIND_MODE}${CLEAR}${L4_TRAIL}"

echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L1}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L2}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L3}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}│${CLEAR}${COLOR_L4}${HYPR_BLUE}  │${CLEAR}"
echo -e "${HYPR_BLUE}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
echo -e "   ${K_DIM2}identity: ${CLEAR}${WHITE}${DEVICE_UNIQ:-${DEVICE_SERIAL:-none}}${CLEAR}  ${K_DIM3}(${DEVICE_ID})${CLEAR}"

# Blacklist check — prevent dangerous button bindings
BLACKLISTED_CODES="1 14 15 28 29 42 54 56 57 97 100 111 272 273 274 275 276 277 278"

if [ "$BIND_MODE" = "combo" ]; then
    CHECK_BTN_CODE="$TRIGGER_BTN_CODE"
    CHECK_BTN_NAME="$TRIGGER_BTN_NAME"
else
    CHECK_BTN_CODE="$TARGET_BTN_CODE"
    CHECK_BTN_NAME="$TARGET_BTN_NAME"
fi

for code in "$CHECK_BTN_CODE" "${MODIFIER_BTN_CODE:-}"; do
    [ -z "$code" ] && continue
    if echo "$BLACKLISTED_CODES" | grep -qw "$code"; then
        if [ "$code" = "$CHECK_BTN_CODE" ]; then
            name="$CHECK_BTN_NAME"
        else
            name="$MODIFIER_BTN_NAME"
        fi
        echo -e ""
        echo -e "${RED}╭─────────────────────────────────────────────────────────────────╮${CLEAR}"
        echo -e "${RED}│${CLEAR} ❌ Button '${WHITE}${name}${CLEAR}' (code ${WHITE}${code}${CLEAR}) is blacklisted.                 ${RED}│${CLEAR}"
        echo -e "${RED}│${CLEAR}    Binding this button would interfere with normal input.       ${RED}│${CLEAR}"
        echo -e "${RED}│${CLEAR}    Please choose a different button (e.g. Guide, Share, etc.)   ${RED}│${CLEAR}"
        echo -e "${RED}╰─────────────────────────────────────────────────────────────────╯${CLEAR}"
        echo -e ""
        echo -e "   ${K_DIM}enter${CLEAR} ${K_DIM2}continue${CLEAR}"
        printf '\033[?25l' >/dev/tty
        read -r -s -n1 </dev/tty || true
        printf '\033[?25h' >/dev/tty
        printf '\0338' >/dev/tty
        printf '\033[J' >/dev/tty
        IS_REDO=1
        continue 2
    fi
done

echo ""
BIND_CONFIRM=""
if command -v gum &>/dev/null; then
    if gum confirm "Want to use this bind?" \
        --affirmative " Use bind " \
        --negative " Redo " \
        --prompt.foreground "#5ECCDF" \
        --selected.foreground "#FFFFFF" \
        --selected.background "#5ECCDF" \
        --unselected.foreground "#CCCCCC" \
        --unselected.background "#2A2A2A" \
        </dev/tty; then
        BIND_CONFIRM="Use bind"
    else
        BIND_CONFIRM="Redo"
    fi
else
    echo -n "Want to use this bind? (y/n): "
    read -r r </dev/tty
    if [[ "$r" =~ ^[Yy]$ ]]; then
        BIND_CONFIRM="Use bind"
    else
        BIND_CONFIRM="Redo"
    fi
fi

if [[ "$BIND_CONFIRM" == *"Redo"* ]]; then
    printf '\0338' >/dev/tty
    printf '\033[J' >/dev/tty
    IS_REDO=1
    continue
fi

break
done
}

# -------------------------------------------------------------------------
# BIND FLOW
# -------------------------------------------------------------------------

# The static header shown at the top of the bind flow. On retry (device not
# connected) the screen is cleared and only this is redrawn.
print_bind_header() {
    banner_calibration
    echo -e "󰌽  Detected OS environment: ${HYPR_BLUE}${DISTRO}${CLEAR} (using ${PKG_MANAGER})"
}

bind_flow() {
    clear
    CALIB_RETRY=0
    FIXED_DEVICE_ID=""
    if [ "${1:-}" = "--device" ]; then
        FIXED_DEVICE_ID="${2:-}"
        if [ -z "$FIXED_DEVICE_ID" ] || [ ! -f "$DEVICES_DIR/$FIXED_DEVICE_ID.conf" ]; then
            echo -e "${RED}Invalid device id.${CLEAR}"
            return 1
        fi
    fi

    print_bind_header

    # -------------------------------------------------------------------------
    # Stop input-remapper + pause binds — runs once before calibration. On
    # retries they stay paused (required for evtest to see events).
    # -------------------------------------------------------------------------
    INPUT_REMAPPER_WAS_ACTIVE=0
    if systemctl is-active --quiet input-remapper 2>/dev/null; then
        INPUT_REMAPPER_WAS_ACTIVE=1
        echo "  input-remapper is running — stopping temporarily for calibration..."
        sudo systemctl stop input-remapper
    fi

    PAUSED_UNITS=()
    while IFS= read -r u; do
        PAUSED_UNITS+=("$u")
    done < <(systemctl --user list-units 'xbox-steam@*.service' --state=active --no-legend --no-pager 2>/dev/null | awk '{print $1}')
    if [ ${#PAUSED_UNITS[@]} -gt 0 ]; then
        echo "  Pausing active binds for calibration..."
        for u in "${PAUSED_UNITS[@]}"; do
            systemctl --user stop "$u" 2>/dev/null || true
        done
        sudo pkill -f "[e]vtest" 2>/dev/null || true
    fi

    # The READY banner + device line belong to the static header — they are not
    # erased on retry, so they stay visible across attempts.
    echo ""
    echo -e "${HYPR_BLUE}  IN${HYPR_DARK_BLUE}PU${HYPR_DARKEST_BLUE}T${HYPR_BLUE} DE${HYPR_DARK_BLUE}VI${HYPR_DARKEST_BLUE}CE${HYPR_BLUE} CALI${HYPR_DARK_BLUE}BRAT${HYPR_DARKEST_BLUE}ION${HYPR_BLUE} RE${HYPR_DARK_BLUE}AD${HYPR_DARKEST_BLUE}Y${CLEAR}"
    if [ -n "$FIXED_DEVICE_ID" ]; then
        FIXED_NAME=$(grep "^TARGET_DEV_NAME=" "$DEVICES_DIR/$FIXED_DEVICE_ID.conf" 2>/dev/null | cut -d'"' -f2)
        [ -z "$FIXED_NAME" ] && FIXED_NAME="$FIXED_DEVICE_ID"
        echo -e "   Rebinding device: ${WHITE}${FIXED_NAME}${CLEAR}"
    fi
    echo -e "   Make sure your input device is turned ${GREEN}ON${CLEAR} and connected."
    echo -e "   You will have ${YELLOW}60 seconds${CLEAR} to press a button."
    echo -e "   Supports ${YELLOW}single${CLEAR} or ${YELLOW}combo${CLEAR} binds (hold first button + press second)."

    printf '\0337' >/dev/tty  # save cursor position (end of header)

    while :; do
        touch /tmp/xbox-steam-calibrating

        calib_rc=0
        calibrate || calib_rc=$?

        trap - INT TERM
        rm -f /tmp/xbox-steam-calibrating

        if [ "$calib_rc" -eq 2 ]; then
            restore_paused
            echo ""
            return 0
        fi
        if [ "$calib_rc" -ne 0 ]; then
            if back_or_retry; then
                restore_paused
                echo ""
                return 0
            fi
            # Retry: restore the cursor to the end of the header and clear the
            # rest of the screen. The header (banner, device line, env, evtest/
            # xpad) stays untouched — no new lines accumulate between attempts.
            CALIB_RETRY=1
            printf '\0338' >/dev/tty
            printf '\033[J' >/dev/tty
            continue
        fi
        restore_paused
        break
    done

    if [ -z "$FIXED_DEVICE_ID" ] && [ -f "$DEVICES_DIR/$DEVICE_ID.conf" ]; then
        if [ -z "${DEVICE_UNIQ:-}" ] && [ -z "${DEVICE_SERIAL:-}" ]; then
            echo -e "   ${YELLOW}⚠  This device has no Uniq/serial — it cannot be told apart from another identical unit.${CLEAR}"
            echo -e "   ${YELLOW}   Both would share this bind.${CLEAR}"
        fi
        if ! confirm "This device is already bound. Replace the existing bind?"; then
            echo -e "${YELLOW}Aborted. Nothing changed.${CLEAR}"
            return 0
        fi
    fi

    echo "─────────────────────────────────────────"

    log_info "Creating configuration directory..."
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config" << EOFCFG
USER_NAME="$USER_NAME"
USER_ID="$USER_ID"
EOFCFG

    log_info "Saving bind: $TARGET_DEV_NAME ($DEVICE_ID)..."
    mkdir -p "$DEVICES_DIR"
    cat > "$DEVICES_DIR/$DEVICE_ID.conf" << EOFC
TARGET_DEV_NAME="$TARGET_DEV_NAME"
DEVICE_UNIQ="$DEVICE_UNIQ"
DEVICE_SERIAL="$DEVICE_SERIAL"
BIND_MODE="$BIND_MODE"
TARGET_BTN_CODE="$TARGET_BTN_CODE"
TARGET_BTN_NAME="$TARGET_BTN_NAME"
MODIFIER_BTN_CODE="$MODIFIER_BTN_CODE"
MODIFIER_BTN_NAME="$MODIFIER_BTN_NAME"
TRIGGER_BTN_CODE="$TRIGGER_BTN_CODE"
TRIGGER_BTN_NAME="$TRIGGER_BTN_NAME"
EOFC

    log_info "Enabling bind for $DEVICE_ID..."
    systemctl --user enable "xbox-steam@$DEVICE_ID.service" &>/dev/null || true
    if ! run_cmd systemctl --user restart "xbox-steam@$DEVICE_ID.service"; then
        log_info "[!] Failed to start service."
    fi

    echo "─────────────────────────────────────────"
    echo -e "${GREEN}  Inst${DARK_GREEN}alla${DARKEST_GREEN}tion${GREEN}/Up${DARK_GREEN}da${DARKEST_GREEN}te${GREEN} com${DARK_GREEN}ple${DARKEST_GREEN}te!${CLEAR}"
    echo "   Your device is mapped dynamically."
    if [ -z "${DEVICE_UNIQ:-}" ] && [ -z "${DEVICE_SERIAL:-}" ]; then
        echo -e "   ${YELLOW}⚠  No Uniq/serial detected — identical controllers of this model share this bind.${CLEAR}"
    fi
    echo "   If it doesn't work, check the log: cat ~/steam_error.log"
    echo ""
    echo -e "   ${K_DIM}enter${CLEAR} ${K_DIM2}continue${CLEAR}"
    printf '\033[?25l' >/dev/tty
    read -r -s -n1 </dev/tty || true
    printf '\033[?25h' >/dev/tty
}

# -------------------------------------------------------------------------
# MAIN MENU
# -------------------------------------------------------------------------
main_menu() {
    local -a items=(
        "  Bind device — Install and calibrate button trigger"
        "  Show bound devices — Manage, toggle or remove binds"
        "  Options — Uninstall binds or the whole program"
        "  Exit"
    )
    local count=${#items[@]} sel=0 key res="" i

    render_main() {
        local pfx
        printf '\033[H\033[J' >/dev/tty
        show_banner >/dev/tty
        echo "" >/dev/tty
        for i in "${!items[@]}"; do
            if [ "$i" -eq "$sel" ]; then
                echo -e "${HYPR_BLUE}${SEL_ARROW}${CLEAR} ${HYPR_BLUE}${items[$i]}${CLEAR}" >/dev/tty
            else
                echo -e "  ${items[$i]}" >/dev/tty
            fi
        done
        echo "" >/dev/tty
        echo -e "  ${K_DIM}←↓↑→${CLEAR} ${K_DIM2}navigate${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}enter${CLEAR} ${K_DIM2}submit${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}esc${CLEAR} ${K_DIM2}exit${CLEAR}" >/dev/tty
        printf '\033[J' >/dev/tty
    }

    printf '\033[?25l' >/dev/tty
    render_main

    while IFS= read -r -s -n1 -t 0.001 _ </dev/tty; do :; done 2>/dev/null || true

    while [ -z "$res" ]; do
        key=$(read_key)
        case "$key" in
            UP)
                [ "$sel" -gt 0 ] && sel=$((sel - 1))
                ;;
            DOWN)
                [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1))
                ;;
            enter)
                res="${items[$sel]}"
                ;;
            ESC|q|Q)
                res="EXIT"
                ;;
        esac
        if [ -z "$res" ]; then
            render_main
        else
            drain_keys
        fi
    done

    printf '\033[%dA' "$((count + 2))" >/dev/tty
    printf '\033[J' >/dev/tty
    printf '\033[?25h' >/dev/tty
    echo "$res"
}

options_menu() {
    local -a items=(
        "  Remove all binds — Remove all binds, keep the program"
        "󱍯  Uninstall program — Remove the whole installation"
        "󰌍  Back"
    )
    local count=${#items[@]} sel=0 key res="" i

    render_options() {
        printf '\033[H\033[J' >/dev/tty
        banner_options >/dev/tty
        echo "" >/dev/tty
        for i in "${!items[@]}"; do
            if [ "$i" -eq "$sel" ]; then
                echo -e "${HYPR_BLUE}${SEL_ARROW}${CLEAR} ${HYPR_BLUE}${items[$i]}${CLEAR}" >/dev/tty
            else
                echo -e "  ${items[$i]}" >/dev/tty
            fi
        done
        echo "" >/dev/tty
        echo -e "  ${K_DIM}←↓↑→${CLEAR} ${K_DIM2}navigate${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}enter${CLEAR} ${K_DIM2}submit${CLEAR}${K_DIM3} • ${CLEAR}${K_DIM}esc${CLEAR} ${K_DIM2}back${CLEAR}" >/dev/tty
        printf '\033[J' >/dev/tty
    }

    printf '\033[?25l' >/dev/tty
    render_options

    while IFS= read -r -s -n1 -t 0.001 _ </dev/tty; do :; done 2>/dev/null || true

    while [ -z "$res" ]; do
        key=$(read_key)
        case "$key" in
            UP)
                [ "$sel" -gt 0 ] && sel=$((sel - 1))
                ;;
            DOWN)
                [ "$sel" -lt $((count - 1)) ] && sel=$((sel + 1))
                ;;
            enter)
                res="${items[$sel]}"
                ;;
            ESC|q|Q)
                res="BACK"
                ;;
        esac
        if [ -z "$res" ]; then
            render_options
        else
            drain_keys
        fi
    done

    printf '\033[%dA' "$((count + 2))" >/dev/tty
    printf '\033[J' >/dev/tty
    printf '\033[?25h' >/dev/tty
    echo "$res"
}

migrate_legacy

# Gate: bind-manager requires install.sh to have run once (systemd unit present).
if [ ! -f "$HOME/.config/systemd/user/xbox-steam@.service" ]; then
    echo -e "${YELLOW}⚠️  Setup not detected.${CLEAR}"
    echo -e "   Run the installer first:"
    echo -e "     ${HYPR_BLUE}curl -sL https://raw.githubusercontent.com/Jeorge01/hyprland-steam-shortcut/main/install.sh | bash${CLEAR}"
    exit 1
fi

# Interactive TUI session reached — clear the terminal on exit.
HSS_INTERACTIVE=1

while true; do
    CHOICE=$(main_menu)

    case "$CHOICE" in
        *"Bind device"*)
            bind_flow
            ;;
        *"Show bound devices"*)
            manage_binds
            ;;
        *"Options"*)
            while :; do
                case "$(options_menu)" in
                    *"Remove all binds"*)
                        "$APP_DIR/uninstall.sh" binds || true
                        ;;
                    *"Uninstall program"*)
                        if "$APP_DIR/uninstall.sh" all; then
                            exit 0
                        fi
                        ;;
                    *)
                        break
                        ;;
                esac
            done
            ;;
        *"Exit"*)
            exit 0
            ;;
        "EXIT")
            exit 0
            ;;
        *)
            echo -e "${RED}No valid selection.${CLEAR}"
            exit 1
            ;;
    esac
done
