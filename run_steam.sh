#!/bin/bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/steam-shortcut"
SCRIPT_PATH="$(realpath "$0")"

if [ -f "$CONFIG_DIR/config" ]; then
    source "$CONFIG_DIR/config"
fi

if [ "$1" == "listen" ]; then
    DEVICE_ID="${2:-}"
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: missing device id. Usage: run_steam.sh listen <device-id>" >&2
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

    PID_FILE="/tmp/xbox-steam-$DEVICE_ID-pids.txt"

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

        if systemctl is-active --quiet input-remapper 2>/dev/null; then
            echo "⚠️ WARNING: input-remapper is running and may block button detection"
            echo "   Run: sudo systemctl stop input-remapper"
        fi

        echo "" > "$PID_FILE"
        LISTENER_PIDS=""

        for NUM in $EVENT_NUMS; do
            if [ -e "/dev/input/$NUM" ]; then
                echo "Listening on /dev/input/$NUM"
                (
                    sudo evtest /dev/input/$NUM 2>/dev/null | while read -r line; do
                        [ -f /tmp/xbox-steam-calibrating ] && continue
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
                                /bin/bash "$SCRIPT_PATH" trigger &
                            fi
                        fi
                    done
                ) &
                LISTENER_PIDS="$LISTENER_PIDS $!"
            fi
        done
        echo "$LISTENER_PIDS" > "$PID_FILE"

        while true; do
            sleep 2
            STILL_CONNECTED=1
            for NUM in $EVENT_NUMS; do
                if [ ! -e "/dev/input/$NUM" ]; then
                    STILL_CONNECTED=0
                    break
                fi
            done
            if [ $STILL_CONNECTED -eq 0 ]; then
                echo "⚠️ Device disconnected! Cleaning up background processes..."
                for pid in $LISTENER_PIDS; do
                    kill $pid 2>/dev/null
                done
                echo "  Re-scanning hardware..."
                break
            fi
        done
    done
    exit 0
fi

# --- TRIGGER EXECUTION ---
if [ "$1" == "trigger" ]; then
    USER_NAME="${USER_NAME:-$(id -un)}"
    [ -f /tmp/xbox-steam-calibrating ] && exit 0
    [ -f "$HOME/steam_error.log" ] && [ $(stat -c%s "$HOME/steam_error.log" 2>/dev/null || echo 0) -gt 524288 ] && mv "$HOME/steam_error.log" "$HOME/steam_error.log.old"

    exec >> "$HOME/steam_error.log" 2>&1
    echo "========================================="
    echo "=== SCRIPT TRIGGERED BY BUTTON PRESS ==="
    echo "Timestamp: $(date)"
    echo "─────────────────────────────────────────"

    export WAYLAND_DISPLAY=$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
    export DISPLAY=$(systemctl --user show-environment | grep '^DISPLAY=' | cut -d= -f2)
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    if [ -z "$WAYLAND_DISPLAY" ]; then
        COMPOSITOR_PID=$(pgrep -u "$USER" -x "Hyprland|sway|wayfire|gnome-shell|kwin_wayland" | head -n 1)

        if [ -n "$COMPOSITOR_PID" ]; then
            export WAYLAND_DISPLAY=$(grep -z '^WAYLAND_DISPLAY=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export DISPLAY=$(grep -z '^DISPLAY=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
            export HYPRLAND_INSTANCE_SIGNATURE=$(grep -z '^HYPRLAND_INSTANCE_SIGNATURE=' /proc/$COMPOSITOR_PID/environ | cut -d= -f2- | tr -d '\0')
        fi
    fi

    [ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY="wayland-0"
    [ -z "$DISPLAY" ] && export DISPLAY=":0"

    CURRENT_ACTIVE_WS=$(hyprctl monitors | awk '/active workspace:/ {print $3; exit}')
    TARGET_WORKSPACE=${CURRENT_ACTIVE_WS:-"1"}
    echo "Current active workspace in focus: $TARGET_WORKSPACE"

    PID_LIST=$(pgrep -u "$USER_NAME" -x "steam")

    if [ -n "$PID_LIST" ]; then
        echo "Steam is running. Searching for Steam window workspace..."

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
            echo "Found Steam on Workspace: $TARGET_WORKSPACE"
        else
            echo "Steam is running but no open window found yet. Staying on current workspace."
        fi
    else
        echo "Steam is not running. It will be launched on the current workspace ($TARGET_WORKSPACE)."
    fi

    echo "Forcing focus to Hyprland Workspace $TARGET_WORKSPACE via modern Lua eval..."
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $TARGET_WORKSPACE }))"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'class:[Ss]team' }))" 2>/dev/null || true
    hyprctl eval "hl.dispatch(hl.dsp.cursor.move_to_corner({ corner = 2, window = 'class:[Ss]team' }))" 2>/dev/null || true

    if [ -n "$PID_LIST" ]; then
        echo "Status: Triggering Big Picture..."
        steam steam://open/bigpicture >/dev/null 2>&1 &
    else
        echo "Status: Launching Big Picture from scratch..."
        systemd-run --user --scope --unit=steam-app steam -bigpicture >/dev/null 2>&1 &
    fi
    echo "=== TRIGGER COMPLETE ==="
    echo "========================================="
fi
