#!/bin/bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/steam-shortcut"
CONFIG_FILE="$CONFIG_DIR/config"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE" >&2
    echo "Run install.sh to generate configuration." >&2
    exit 1
fi

SCRIPT_PATH="$(realpath "$0")"

if [ "$1" == "listen" ]; then
    echo "Starting listener..."

    while true; do
        until awk -v name="$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=0} index($0, "N: Name=\"" name) == 1' /proc/bus/input/devices >/dev/null 2>&1; do
            echo "Waiting for your specific controller ($TARGET_DEV_NAME) to initialize..."
            sleep 2
        done

        EVENT_NUMS=$(awk -v name="$TARGET_DEV_NAME" 'BEGIN{IGNORECASE=0} index($0, "N: Name=\"" name) == 1 {cat=1} cat && /Handlers=/{for(i=1;i<=NF;i++) if($i~/event/) print $i; cat=0}' /proc/bus/input/devices | grep -oE '[0-9]+')

        for NUM in $EVENT_NUMS; do
            until [ -r "/dev/input/event$NUM" ]; do
                echo "Waiting for /dev/input/event$NUM to become readable..."
                sleep 0.2
            done
        done

        echo "Your calibrated device is ready! Initializing listener..."

        if systemctl is-active --quiet input-remapper 2>/dev/null; then
            echo "⚠️ WARNING: input-remapper is running and may block button detection"
            echo "   Run: sudo systemctl stop input-remapper"
        fi

        echo "" > /tmp/xbox-steam-pids.txt
        LISTENER_PIDS=""

        for NUM in $EVENT_NUMS; do
            if [ -e "/dev/input/event$NUM" ]; then
                echo "Listening on /dev/input/event$NUM"
                (
                    sudo evtest /dev/input/event$NUM 2>/dev/null | while read -r line; do
                        [ -f /tmp/xbox-steam-calibrating ] && continue
                        echo "[DEBUG-EV] $line" >> "$HOME/steam_error.log"
                        if [ "$BIND_MODE" = "combo" ]; then
                            if echo "$line" | grep -q "code $MODIFIER_BTN_CODE.*value 1"; then
                                MODIFIER_HELD=1
                                echo "[DEBUG-COMBO] Modifier $MODIFIER_BTN_NAME HELD (code $MODIFIER_BTN_CODE)" >> "$HOME/steam_error.log"
                            fi
                            if echo "$line" | grep -q "code $MODIFIER_BTN_CODE.*value 0"; then
                                MODIFIER_HELD=0
                                echo "[DEBUG-COMBO] Modifier $MODIFIER_BTN_NAME RELEASED" >> "$HOME/steam_error.log"
                            fi
                            if echo "$line" | grep -q "code $TRIGGER_BTN_CODE.*value 1"; then
                                echo "[DEBUG-COMBO] Trigger $TRIGGER_BTN_NAME detected! MODIFIER_HELD=${MODIFIER_HELD:-0}" >> "$HOME/steam_error.log"
                                if [ "${MODIFIER_HELD:-0}" -eq 1 ]; then
                                    MODIFIER_HELD=0
                                    echo "[DEBUG-COMBO] >>> COMBO FIRE <<<" >> "$HOME/steam_error.log"
                                    /bin/bash "$SCRIPT_PATH" trigger &
                                else
                                    echo "[DEBUG-COMBO] Trigger IGNORED (modifier not held)" >> "$HOME/steam_error.log"
                                fi
                            fi
                        else
                            if echo "$line" | grep -q "code $TARGET_BTN_CODE.*value 1"; then
                                echo "[DEBUG-SINGLE] Single trigger fired!" >> "$HOME/steam_error.log"
                                /bin/bash "$SCRIPT_PATH" trigger &
                            fi
                        fi
                    done
                ) &
                LISTENER_PIDS="$LISTENER_PIDS $!"
            fi
        done
        echo "$LISTENER_PIDS" > /tmp/xbox-steam-pids.txt

        while true; do
            sleep 2
            STILL_CONNECTED=1

            for NUM in $EVENT_NUMS; do
                if [ ! -e "/dev/input/event$NUM" ]; then
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
