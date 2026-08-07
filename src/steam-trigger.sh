#!/bin/bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/steam-shortcut"
SCRIPT_PATH="$(realpath "$0")"
APP_DIR="$(dirname "$SCRIPT_PATH")"

if [ -f "$CONFIG_DIR/config" ]; then
    source "$CONFIG_DIR/config"
fi

if [ "$1" == "listen" ]; then
    DEVICE_ID="${2:-}"
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: missing device id. Usage: steam-trigger.sh listen <device-id>" >&2
        exit 1
    fi

    CONFIG_FILE="$CONFIG_DIR/devices/$DEVICE_ID.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file not found at $CONFIG_FILE" >&2
        exit 1
    fi
    source "$CONFIG_FILE"

    # Normalizes a per-instance identity (input Uniq or USB serial) into a safe
    # systemd instance-name part: lowercase, alnum kept, runs of other chars -> '-'.
    sanitize_id_part() {
        echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-\+//; s/-\+$//' | cut -c1-40
    }

    # USB iSerialNumber (if any) of the USB device owning an input event node.
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

    # The input U: Uniq value of the /proc record owning an event node.
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
    # Steam Input clones have empty Phys and are excluded.
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

    # Returns 0 (true) when another process holds an exclusive grab (EVIOCGRAB)
    # on the node — input-remapper, Steam Input, hkdm, etc. A passive evtest
    # reader receives no events from a grabbed node. Probes with a short
    # `evtest --grab`: on a grabbed device the grab is denied (evtest prints
    # "grabbed by another process" and exits non-zero); on a free device the
    # probe holds the grab only until the timeout releases it.
    node_is_grabbed() {
        local node="$1" out rc
        out=$(timeout 2 sudo -n evtest --grab "$node" 2>&1)
        rc=$?
        echo "$out" | grep -qi "grabbed by another process" && return 0
        [ "$rc" -eq 2 ] && return 0
        return 1
    }

    # Event nodes of virtual clones of the device: same VID/PID, non-empty Phys,
    # living under /sys/devices/virtual/input/. A grabber such as input-remapper
    # creates one per grabbed controller (e.g. "input-remapper <name> forwarded",
    # Phys=py-evdev-uinput) so other processes can keep reading input while the
    # physical node is exclusively grabbed. Steam Input clones (empty Phys) are
    # excluded, matching device_events().
    forwarded_events() {
        local id="$1" name="${2:-}" vid="" pid="" rest=""
        if [[ "$id" =~ ^[0-9a-fA-F]{4}-[0-9a-fA-F]{4}(-[a-z0-9]+)*$ ]]; then
            vid=$(echo "${id%%-*}" | tr '[:upper:]' '[:lower:]')
            rest="${id#*-}"
            pid=$(echo "${rest%%-*}" | tr '[:upper:]' '[:lower:]')
        fi
        awk -v RS='' -v vid="$vid" -v pid="$pid" -v name="$name" '
            function physval(    s, p) {
                p = index($0, "P: Phys="); if (!p) return ""
                s = substr($0, p + 8); sub(/\n.*/, "", s); return s
            }
            index($0, "Sysfs=/devices/virtual/input/") && physval() != "" &&
            (vid != "" ? index($0, "Vendor=" vid " ") && index($0, "Product=" pid " ") : index($0, name)) {
                for (i = 1; i <= NF; i++) if ($i ~ /^(Handlers=)?event[0-9]+$/) { sub(/^Handlers=/, "", $i); print $i }
            }' /proc/bus/input/devices 2>/dev/null
    }

    # Logs a diagnostic line to the journal under the `hss-trigger` tag so it
    # shows up in `journalctl --user -t hss-trigger -f`, while still reaching
    # the service journal via stdout.
    hss_log() {
        if command -v systemd-cat >/dev/null 2>&1; then
            printf '%s\n' "$*" | systemd-cat -t hss-trigger 2>/dev/null || true
        fi
        printf '%s\n' "$*"
    }

    # Returns 0 when the installed root helper advertises --holders support
    # (HSS_EVTEST_STOP_VERSION >= 1). Legacy helpers from one generation have
    # the flag but no constant, and are probed by the literal string. Never
    # call the helper with --holders unless this passes — an ancient helper
    # without --holders support would misread it as a node and pkill the
    # listener's own evtest.
    hss_evtest_stop_supports_holders() {
        [ -f /usr/local/sbin/hss-evtest-stop ] || return 1
        awk -F= '/^HSS_EVTEST_STOP_VERSION=/{v=$2} END { exit !(v >= 1) }' \
            /usr/local/sbin/hss-evtest-stop 2>/dev/null || \
            grep -q -- '--holders' /usr/local/sbin/hss-evtest-stop 2>/dev/null
    }

    # Returns a formatted suffix naming who holds the given nodes, or empty.
    # Primary source is the root helper's --holders mode (fuser), which shows
    # the real grabbing process even when it runs as root. If the helper is
    # missing or too old, falls back to a clearly-labelled guess from running
    # grabber processes.
    grab_holders() {
        local nodes="$1" out suffix="" guesses=""
        if hss_evtest_stop_supports_holders; then
            out=$(sudo -n /usr/local/sbin/hss-evtest-stop --holders $nodes 2>&1)
            if [ -n "$out" ] && ! printf '%s\n' "$out" | grep -qi "command not found\|not authorized\|password is required\|usage"; then
                suffix=$(printf '%s\n' "$out" | awk '
                    function prog(p) { sub(/^.*\//, "", p); return p }
                    $1 ~ /^\/dev\/input\// { pid = $3; cmd = prog($5); check(); next }
                    $2 ~ /^[0-9]+$/ { pid = $2; cmd = prog($4); check() }
                    function check() {
                        if (cmd == "" || cmd == "fuser" || cmd == "evtest" || cmd == "sudo" ||
                            cmd == "bash" || cmd == "sh" || cmd == "systemd-cat" ||
                            cmd == "timeout" || cmd == "hss-evtest-stop") next
                        printf " by: %s(%d)", cmd, pid
                    }')
            fi
        fi
        if [ -z "$suffix" ]; then
            for pat in input-remapper steam hkdm keyd; do
                pgrep -f "$pat" >/dev/null 2>&1 && guesses="$guesses $pat"
            done
            [ -n "$guesses" ] && suffix=" (possible grabber:$guesses)"
        fi
        printf '%s' "$suffix"
    }

    # Spawns one evtest listener per node in the active set. Detects exclusive
    # grabs (input-remapper, Steam Input, hkdm, ...) on the physical nodes and,
    # when grabbed, listens on the grabber's forwarded virtual clone instead so
    # the bind keeps working while the grabber holds the device. Kills any
    # previous listeners first, so it can be called again to swap between the
    # physical device and the forwarded clone when the grab state changes.
    spawn_listeners() {
        FREE_NUMS=""
        GRABBED_NUMS=""
        for NUM in $EVENT_NUMS; do
            if [ -e "/dev/input/$NUM" ] && node_is_grabbed "/dev/input/$NUM"; then
                GRABBED_NUMS="$GRABBED_NUMS $NUM"
            else
                FREE_NUMS="$FREE_NUMS $NUM"
            fi
        done

        FORWARDED_NUMS=$(forwarded_events "$DEVICE_ID" "$TARGET_DEV_NAME")
        if [ -n "$GRABBED_NUMS" ]; then
            HOLDERS=$(grab_holders "$(echo $GRABBED_NUMS)")
            if [ -n "$FORWARDED_NUMS" ]; then
                hss_log "⚠️ Controller grabbed$HOLDERS — listening on forwarded virtual device(s):$FORWARDED_NUMS"
            else
                hss_log "⚠️ WARNING: controller grabbed$HOLDERS and no forwarded virtual device was found."
                hss_log "   No events will reach this listener."
                hss_log "   Check who holds it: fuser -v /dev/input/$(echo $GRABBED_NUMS)"
            fi
        fi

        LISTEN_NUMS="$FREE_NUMS $FORWARDED_NUMS"

        cleanup_listeners
        echo "" > "$PID_FILE"
        : > "$NODES_FILE"
        LISTENER_PIDS=""

        for NUM in $LISTEN_NUMS; do
            if [ -e "/dev/input/$NUM" ]; then
                hss_log "Listening on /dev/input/$NUM"
                echo "$NUM" >> "$NODES_FILE"
                (
                    LAST_TRIGGER_AT=0
                    sudo -n evtest /dev/input/$NUM 2>/dev/null | while read -r line; do
                        [ -f /tmp/hss-steam-trigger-calibrating ] && continue
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
                            if echo "$line" | grep -q "code $TARGET_BTN_CODE.*value 1"; then
                                # Coalesce rapid presses into one toggle. Steam's
                                # Big Picture menu animation (~200ms) swallows
                                # back-to-back Ctrl+1 injections, so spamming the
                                # guide button leaves the menu stuck open. Only the
                                # first press in a TRIGGER_COALESCE_MS window toggles.
                                NOW=$(date +%s%N)
                                if [ $(( NOW - LAST_TRIGGER_AT )) -ge $(( ${TRIGGER_COALESCE_MS:-300} * 1000000 )) ]; then
                                    LAST_TRIGGER_AT=$NOW
                                    /bin/bash "$SCRIPT_PATH" trigger &
                                fi
                            fi
                        fi
                    done
                ) &
                LISTENER_PIDS="$LISTENER_PIDS $!"
            fi
        done
        echo "$LISTENER_PIDS" > "$PID_FILE"
    }

    PID_FILE="/tmp/hss-steam-trigger-$DEVICE_ID-pids.txt"
    NODES_FILE="/tmp/hss-steam-trigger-$DEVICE_ID-nodes.txt"

    # Kills this device's listeners. The evtest subprocesses run as root (sudo),
    # so the user systemd manager cannot kill them with its cgroup kill — they
    # must be terminated explicitly via the NOPASSWD helper. Called on device
    # disconnect, on service stop (EXIT/INT/TERM trap) and from ExecStop.
    cleanup_listeners() {
        [ -f "$PID_FILE" ] && xargs kill < "$PID_FILE" 2>/dev/null || true
        rm -f "$PID_FILE"
        if [ -f "$NODES_FILE" ]; then
            sudo -n /usr/local/sbin/hss-evtest-stop $(cat "$NODES_FILE") 2>/dev/null || true
            rm -f "$NODES_FILE"
        fi
    }
    trap 'cleanup_listeners; exit 0' EXIT INT TERM

    echo "Starting listener for $TARGET_DEV_NAME ($DEVICE_ID)..."

    while true; do
        until [ -n "$(device_events "$DEVICE_ID" "$TARGET_DEV_NAME" "${DEVICE_UNIQ:-}")" ]; do
            echo "Waiting for your controller ($TARGET_DEV_NAME) to initialize..."
            sleep 2
        done

        EVENT_NUMS=$(device_events "$DEVICE_ID" "$TARGET_DEV_NAME" "${DEVICE_UNIQ:-}")

        for NUM in $EVENT_NUMS; do
            until [ -r "/dev/input/$NUM" ]; do
                echo "Waiting for /dev/input/$NUM to become readable..."
                sleep 0.2
            done
        done

        echo "Your calibrated device is ready! Initializing listener..."
        spawn_listeners

        while true; do
            sleep 2
            STILL_CONNECTED=1
            MISSING_NUMS=""
            for NUM in $EVENT_NUMS $FORWARDED_NUMS; do
                if [ ! -e "/dev/input/$NUM" ]; then
                    STILL_CONNECTED=0
                    MISSING_NUMS="$NUM"
                    break
                fi
            done
            if [ $STILL_CONNECTED -eq 0 ]; then
                # A forwarded clone vanishing means a grabber released the
                # device; a physical node vanishing means the controller was
                # unplugged. Both re-scan, but the message should say which.
                case " $FORWARDED_NUMS " in
                    *" $MISSING_NUMS "*)
                        hss_log "⚠️ Forwarded virtual device $MISSING_NUMS disappeared — grabber released? Re-evaluating listeners..."
                        ;;
                    *)
                        hss_log "⚠️ Device disconnected! Cleaning up background processes..."
                        ;;
                esac
                cleanup_listeners
                hss_log "Re-scanning hardware..."
                break
            fi

            # Grab state may have changed while running (a grabber such as
            # input-remapper or Steam Input started or stopped). Forwarded
            # virtual clones appear and disappear with the grab, so comparing
            # that set cheaply tells us when to re-evaluate and swap listeners.
            CURRENT_FORWARDED=$(forwarded_events "$DEVICE_ID" "$TARGET_DEV_NAME")
            if [ "$CURRENT_FORWARDED" != "$FORWARDED_NUMS" ]; then
                hss_log "⚠️ Forwarded virtual device set changed — re-evaluating listeners..."
                break
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
if [ "$1" == "trigger" ]; then
    USER_NAME="${USER_NAME:-$(id -un)}"
    [ -f /tmp/hss-steam-trigger-calibrating ] && exit 0

    # Resolves the command used to control Steam: the native binary, or the
    # Flatpak app (flatpak run com.valvesoftware.Steam). Empty when neither is
    # installed. STEAM_CMD is an array so flatpak's multi-word prefix stays one
    # unit.
    detect_steam() {
        if command -v steam >/dev/null 2>&1; then
            STEAM_CMD=(steam)
        elif command -v flatpak >/dev/null 2>&1 && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
            STEAM_CMD=(flatpak run com.valvesoftware.Steam)
        else
            STEAM_CMD=()
        fi
    }
    detect_steam

    # Route trigger output to the systemd journal instead of a file in $HOME:
    # the trigger runs as a background child of the listener subshell, whose
    # stdout is a pipe read-end, so it must be redirected explicitly. Follow
    # the output with: journalctl --user -t hss-trigger -f
    if command -v systemd-cat >/dev/null 2>&1; then
        exec > >(systemd-cat -t hss-trigger) 2>&1
    else
        exec > /dev/null 2>&1
    fi

    export WAYLAND_DISPLAY=$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
    export DISPLAY=$(systemctl --user show-environment | grep '^DISPLAY=' | cut -d= -f2)
    export HYPRLAND_INSTANCE_SIGNATURE=$(systemctl --user show-environment | grep '^HYPRLAND_INSTANCE_SIGNATURE=' | cut -d= -f2)
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        COMPOSITOR_PID=$(pgrep -u "$USER_NAME" -x "Hyprland|sway|wayfire|gnome-shell|kwin_wayland" | head -n 1)

        if [ -n "$COMPOSITOR_PID" ]; then
            [ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=$(grep -z '^WAYLAND_DISPLAY=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            [ -z "$DISPLAY" ] && export DISPLAY=$(grep -z '^DISPLAY=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ] && export HYPRLAND_INSTANCE_SIGNATURE=$(grep -z '^HYPRLAND_INSTANCE_SIGNATURE=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
        fi
    fi

    [ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY="wayland-0"
    [ -z "$DISPLAY" ] && export DISPLAY=":0"

    CURRENT_ACTIVE_WS=$(hyprctl monitors | awk '/active workspace:/ {print $3; exit}')
    TARGET_WORKSPACE=${CURRENT_ACTIVE_WS:-"1"}

    # A running game takes precedence over Steam Big Picture: focus the game
    # instead of Steam, so the bind never yanks focus away from it. A game is
    # detected primarily by the `SteamAppId` env var Steam sets on every
    # process of a game session (native, Proton and Gamescope alike), mapped
    # to a window via its PID. Class names alone are unreliable: games choose
    # their own (e.g. `gamescope`, `winehq`, or the game's own name), so the
    # class heuristics below are only a fallback for games launched outside
    # Steam (no SteamAppId). Steam's own guide-button overlay still works on
    # top of the game; the game itself decides where its input goes.
    STEAM_PIDS=$(grep -azl '^SteamAppId=' /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3 | tr '\n' ' ')

    GAME=$(hyprctl clients | awk -v active_ws="$CURRENT_ACTIVE_WS" -v steam_pids="$STEAM_PIDS" '
        BEGIN { done=0; best=""; best_ws=""; best_addr=""; best_fh=9999 }
        function is_steam_pid(p) { return (" " steam_pids " ") ~ (" " p " ") }
        function is_game() {
            if (is_steam_pid(pid)) return 1
            if (cls ~ /^steam_app_/) return 1
            if (cls == "gamescope" && title !~ /^Steam (Big Picture Mode|Deck UI|Desktop UI|Beta)/) return 1
            return 0
        }
        function flush() {
            if (done) return
            if (is_game() && ws != "" && addr != "") {
                if (ws == active_ws) { print cls, ws, addr, title; done=1; return }
                if (fh < best_fh) { best=cls; best_ws=ws; best_addr=addr; best_fh=fh; best_title=title }
            }
            ws=""; cls=""; addr=""; fh=9999; title=""
        }
        /^Window/ { flush(); addr=$2 }
        /^[[:space:]]*workspace:/ { ws=$2 }
        /^[[:space:]]*class:/ { cls=$2 }
        /^[[:space:]]*pid:/ { pid=$2 }
        /^[[:space:]]*focusHistoryID:/ { fh=$2 }
        /^[[:space:]]*title:/ { sub(/^[[:space:]]*title: /, ""); title=$0 }
        END { flush(); if (!done && best != "") print best, best_ws, best_addr, best_title }
    ')

    if [ -n "$GAME" ]; then
        read -r GAME_CLASS GAME_WS GAME_ADDR GAME_TITLE <<< "$GAME"
        GAME_ADDR_0X="0x${GAME_ADDR#0x}"
        echo "Game running — focusing $GAME_TITLE on workspace $GAME_WS"
        hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $GAME_WS }))" >/dev/null 2>&1 || true
        hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$GAME_ADDR_0X' }))" >/dev/null 2>&1 || true
        hyprctl eval "hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 2, window = 'address:$GAME_ADDR_0X' }))" >/dev/null 2>&1 || true
        echo "Trigger complete"
        exit 0
    fi

    echo "Trigger: opening Steam Big Picture"

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
            echo "Steam running on workspace $TARGET_WORKSPACE"
        else
            echo "Steam running but no window yet — staying on workspace $TARGET_WORKSPACE"
        fi
    else
        echo "Steam not running — launching on workspace $TARGET_WORKSPACE"
    fi

    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $TARGET_WORKSPACE }))" >/dev/null 2>&1 || true
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'class:[Ss]team' }))" >/dev/null 2>&1 || true
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 2, window = 'class:[Ss]team' }))" >/dev/null 2>&1 || true

    if [ -n "$PID_LIST" ]; then
        # Steam is already running: toggle its Big Picture menu (the same menu
        # the guide button opens on a Deck) instead of just focusing it. Ctrl+1
        # is injected via uinput by steam-guide-btn-fix.sh toggle — the window
        # was focused above, so the keystroke lands in Steam without the mouse.
        if [ -x "$APP_DIR/steam-guide-btn-fix.sh" ]; then
            "$APP_DIR/steam-guide-btn-fix.sh" toggle >/dev/null 2>&1 || \
                "${STEAM_CMD[@]}" steam://open/bigpicture >/dev/null 2>&1 &
        else
            "${STEAM_CMD[@]}" steam://open/bigpicture >/dev/null 2>&1 &
        fi
    else
        # Re-apply the Steam Input guide-unbind before every fresh launch.
        # Steam regenerates the mapping (with the guide button bound) whenever
        # the controller is reset/remapped in "Setup Device Inputs", so this
        # re-injects the no-guide entries while Steam is still closed. It is
        # idempotent: when the entries are already present it changes nothing.
        if [ -x "$APP_DIR/steam-guide-btn-fix.sh" ]; then
            "$APP_DIR/steam-guide-btn-fix.sh" setup --global-off >/dev/null 2>&1 || true
        fi
        # systemd-run scopes are not cleaned up when Steam exits, so a stale
        # `steam-app` unit from an earlier launch would make this fail silently
        # and Steam would never start. Use a unique unit name per launch plus
        # --collect so finished scopes are reaped and nothing can collide.
        systemd-run --user --scope --collect --unit="steam-app-$(date +%s%N)" "${STEAM_CMD[@]}" -bigpicture >/dev/null 2>&1 &
    fi
    echo "Trigger complete"
fi
