#!/bin/bash
#
# steam-guide-btn-fix.sh — one file for everything the Steam guide button
# needs: `setup` (Steam closed), `revert` (undo setup) and `toggle` (Steam
# running).
#
# Subcommands:
#
#   steam-guide-btn-fix.sh setup [appid ...]
#       Per-game Steam Input off for the given appids (UseSteamControllerConfig
#       = 0 in localconfig.vdf). Steam must be closed.
#
#   steam-guide-btn-fix.sh setup --global-off [--force] [appid ...]
#       Same as above, plus the global guide-button fixes: unbind the guide
#       button from Steam's SDL gamepad mapping, set Controller_CheckGuideButton
#       = 0 and SteamController_XBoxSupport = 0. This is what keeps the guide
#       button away from Steam so it can never steal focus from a game.
#
#   steam-guide-btn-fix.sh setup --device <vid-pid> [--force]
#       Unbind the guide button from Steam's SDL gamepad mapping for ONE
#       controller only (matched by vid-pid, e.g. 045e-028e). No global keys
#       are touched. This is what bind-manager.sh runs when a bind is saved.
#
#   steam-guide-btn-fix.sh revert [--force]
#       Restore config.vdf / localconfig.vdf from the .bak backups made by
#       `setup`, undoing every guide button patch. This is what uninstall.sh
#       runs so Steam is fully back to normal after uninstalling.
#
#   steam-guide-btn-fix.sh toggle
#       Inject Ctrl+1 (the STEAM button shortcut) into the focused window to
#       toggle the Big Picture menu. The caller must have the Steam window
#       focused first. Uses uinput (compiled from uinputctl.c, same dir).
#       (wtype was evaluated but Hyprland 0.56.1 forwards raw keycodes that
#       resolve to NoSymbol, so uinput remains the reliable path.)
#
# Options for `setup`/`revert`:
#   --device <vid-pid>   Only unbind the guide button for this controller.
#   --force   Close Steam automatically before patching.
#   -h        Show this help.
#
# Notes:
#   - Steam rewrites localconfig.vdf / config.vdf from its in-memory copy when
#     it exits, so `setup`/`revert` must run while Steam is down (or --force).
#   - Steam regenerates the SDL mapping (with the guide bound) whenever the
#     controller is reset in "Setup Device Inputs", so steam-trigger.sh re-runs
#     `setup --global-off` before every fresh Steam launch. It is idempotent.

set -u

MODE="${1:-}"
shift 2>/dev/null || true

case "$MODE" in
    setup)
        ;;
    revert)
        MODE_REVERT=1
        ;;
    toggle)
        MODE_TOGGLE=1
        ;;
    -h|--help)
        sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Usage: $0 setup [--global-off] [--device <vid-pid>] [--force] [appid ...] | revert [--force] | toggle" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# MODE: toggle — inject Ctrl+1 into the focused window
# ---------------------------------------------------------------------------
if [ "${MODE_TOGGLE:-0}" -eq 1 ]; then
    APP_DIR="$(dirname "$(realpath "$0")")"
    INJECTOR="$APP_DIR/uinputctl"
    SRC="$APP_DIR/uinputctl.c"

    if [ ! -x "$INJECTOR" ]; then
        if ! command -v gcc >/dev/null 2>&1; then
            echo "steam-guide-btn-fix: gcc not found, cannot build $INJECTOR" >&2
            exit 1
        fi
        if [ ! -f "$SRC" ]; then
            echo "steam-guide-btn-fix: missing $SRC" >&2
            exit 1
        fi
        if ! gcc -O2 -o "$INJECTOR" "$SRC" 2>/dev/null; then
            echo "steam-guide-btn-fix: failed to build $INJECTOR" >&2
            exit 1
        fi
    elif [ "$SRC" -nt "$INJECTOR" ]; then
        gcc -O2 -o "$INJECTOR" "$SRC" 2>/dev/null || true
    fi

    exec "$INJECTOR" chord ctrlleft 1
fi

# ---------------------------------------------------------------------------
# MODE: revert — restore Steam's config files from the backups setup made
# ---------------------------------------------------------------------------
if [ "${MODE_REVERT:-0}" -eq 1 ]; then
    FORCE=0
    for arg in "$@"; do
        case "$arg" in
            --force) FORCE=1 ;;
            *) echo "Invalid argument: '$arg'" >&2; exit 1 ;;
        esac
    done

    if pgrep -x steam >/dev/null 2>&1; then
        if [ "$FORCE" -eq 1 ]; then
            echo "Steam is running — closing it..."
            steam -shutdown >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do
                pgrep -x steam >/dev/null 2>&1 || break
                sleep 1
            done
            if pgrep -x steam >/dev/null 2>&1; then
                echo "Steam did not exit within 30s — aborting." >&2
                exit 1
            fi
            echo "Steam closed."
        else
            echo "Steam is running — close it first (or rerun with --force)." >&2
            echo "Steam rewrites config.vdf / localconfig.vdf from memory on exit, which would undo the restore." >&2
            exit 1
        fi
    fi

    restored=0
    for dir in "$HOME/.local/share/Steam" \
                "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
        [ -d "$dir" ] || continue
        if [ -f "$dir/config/config.vdf.bak" ]; then
            cp "$dir/config/config.vdf.bak" "$dir/config/config.vdf"
            rm -f "$dir/config/config.vdf.bak"
            echo "  Restored $dir/config/config.vdf from backup."
            restored=1
        else
            echo "  $dir/config/config.vdf: no backup — left as-is."
        fi
    done

    for base in "$HOME/.local/share/Steam/userdata" \
                "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/userdata"; do
        [ -d "$base" ] || continue
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            target="${f%.bak}"
            cp "$f" "$target"
            rm -f "$f"
            echo "  Restored $target from backup."
            restored=1
        done < <(find "$base" -maxdepth 3 -name localconfig.vdf.bak 2>/dev/null)
    done

    echo ""
    if [ "$restored" -eq 1 ]; then
        echo "Done. Steam's controller configuration is back to its pre-fix state."
        echo "Restart Steam — the guide button, Xbox Configuration Support and"
        echo "per-game Steam Input are restored."
    else
        echo "No backups found — nothing to restore."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# MODE: setup — patch Steam config files (VDF) while Steam is closed
# ---------------------------------------------------------------------------

GLOBAL_OFF=0
FORCE=0
DEVICE=""
APPIDS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --global-off) GLOBAL_OFF=1; shift ;;
        --force) FORCE=1; shift ;;
        --device)
            DEVICE="${2:-}"
            shift 2 2>/dev/null || true
            ;;
        *)
            case "$1" in
                ''|*[!0-9]*) echo "Invalid argument or Steam app ID: '$1'" >&2; exit 1 ;;
                *) APPIDS+=("$1"); shift ;;
            esac
            ;;
    esac
done

# Normalize a vid-pid device id (045e-028e or 045e/028e) to 045e/028e.
if [ -n "$DEVICE" ]; then
    DEVICE="$(printf '%s' "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '/')"
    case "$DEVICE" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f]/[0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
        *)
            echo "Invalid --device: '$DEVICE' — expected a vid-pid like 045e-028e." >&2
            exit 1
            ;;
    esac
    # Steam's controller.txt writes vid/pid without leading zeros (45e/28e),
    # so build the zero-stripped form used to match the log.
    v="$(printf '%s' "${DEVICE%/*}" | sed 's/^0*//')"
    p="$(printf '%s' "${DEVICE#*/}" | sed 's/^0*//')"
    [ -z "$v" ] && v=0
    [ -z "$p" ] && p=0
    DEVKEY="$v/$p"
fi

if pgrep -x steam >/dev/null 2>&1; then
    if [ "$FORCE" -eq 1 ]; then
        echo "Steam is running — closing it..."
        steam -shutdown >/dev/null 2>&1 || true
        for _ in $(seq 1 30); do
            pgrep -x steam >/dev/null 2>&1 || break
            sleep 1
        done
        if pgrep -x steam >/dev/null 2>&1; then
            echo "Steam did not exit within 30s — aborting." >&2
            exit 1
        fi
        echo "Steam closed."
    else
        echo "Steam is running — close it first (or rerun with --force)." >&2
        echo "Steam rewrites localconfig.vdf from memory on exit, which would undo the patch." >&2
        exit 1
    fi
fi

FILES=()
for base in "$HOME/.local/share/Steam/userdata" \
            "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/userdata"; do
    [ -d "$base" ] || continue
    while IFS= read -r f; do
        FILES+=("$f")
    done < <(find "$base" -maxdepth 3 -name localconfig.vdf 2>/dev/null)
done

if [ -z "$DEVICE" ] && [ ${#FILES[@]} -eq 0 ]; then
    echo "No localconfig.vdf found under the Steam userdata directories." >&2
    exit 1
fi

STEAM_DIRS=()
for dir in "$HOME/.local/share/Steam" \
            "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
    [ -d "$dir" ] && STEAM_DIRS+=("$dir")
done

# Patch one appid in one localconfig.vdf. The awk tracks the "apps" section
# (same "12345" keys exist in many other sections) and, inside it, the target
# app block. It replaces an existing UseSteamControllerConfig value, inserts
# one if the block exists without it, or creates the block if missing.
patch_file() {
    local file="$1" appid="$2"
    local tmp
    tmp="$(mktemp)"

    if awk -v appid="$appid" '
        function close_app_block() {
            if (in_block && appid_cur == appid && !patched) {
                print "\t\t\t\"UseSteamControllerConfig\"\t\t\"0\""
            }
            in_block = 0; appid_cur = ""; patched = 0
        }
        BEGIN { in_apps = 0; in_block = 0; expect_block = 0; depth = 0; appid_cur = ""; patched = 0; found = 0 }
        {
            if (!in_apps) {
                # The settings "apps" section is a top-level sibling of
                # "depots"/"friends" (one tab). Other "apps" sections (per-app
                # cloud/launch data) sit deeper and must be ignored.
                if ($0 ~ /^\t"apps"[[:space:]]*$/) in_apps = 1
                print; next
            }
            if (in_block) {
                if ($0 ~ /^[[:space:]]*\{/) { depth++; print; next }
                if ($0 ~ /^[[:space:]]*\}[[:space:]]*$/) {
                    depth--
                    if (depth == 0) { close_app_block(); print; next }
                    print; next
                }
                if (appid_cur == appid && $0 ~ /"UseSteamControllerConfig"/) {
                    print "\t\t\t\"UseSteamControllerConfig\"\t\t\"0\""
                    patched = 1
                    next
                }
                print; next
            }
            if ($0 ~ /^[[:space:]]*"[0-9]+"[[:space:]]*$/) {
                appid_cur = $0; gsub(/[^0-9]/, "", appid_cur)
                if (appid_cur == appid) found = 1
                expect_block = 1
                print; next
            }
            if ($0 ~ /^[[:space:]]*\{/) {
                if (expect_block) { in_block = 1; depth = 1; expect_block = 0 }
                print; next
            }
            if ($0 ~ /^[[:space:]]*\}/) {
                if (!found) {
                    print "\t\t\"" appid "\""
                    print "\t\t{"
                    print "\t\t\t\"UseSteamControllerConfig\"\t\t\"0\""
                    print "\t\t}"
                }
                in_apps = 0
                print; next
            }
            print; next
        }
    ' "$file" > "$tmp"; then
        if cmp -s "$tmp" "$file"; then
            rm -f "$tmp"
            return 0
        fi
        cp "$file" "$file.bak"
        cp "$tmp" "$file"
        rm -f "$tmp"
        echo "  Patched $file: app $appid → UseSteamControllerConfig=0"
        return 1
    fi

    rm -f "$tmp"
    return 0
}

# Turn off Steam's global Xbox pad support (SteamController_XBoxSupport = 0).
# This stops Steam from reading the physical pad entirely, which kills the
# desktop-config and guide-button reactions that the per-game override alone
# cannot reach. Only the active account's file has the key; inactive accounts
# are skipped.
patch_global() {
    local file="$1"
    local tmp
    tmp="$(mktemp)"

    if awk '
        BEGIN { found = 0 }
        /"SteamController_XBoxSupport"/ {
            sub(/"[0-9]+"/, "\"0\"")
            found = 1
            print; next
        }
        { print }
        END { if (!found) exit 2 }
    ' "$file" > "$tmp"; then
        if cmp -s "$tmp" "$file"; then
            echo "  $file: SteamController_XBoxSupport already 0"
        else
            cp "$file" "$file.bak"
            cp "$tmp" "$file"
            echo "  Patched $file: SteamController_XBoxSupport → 0"
        fi
    else
        echo "  $file: SteamController_XBoxSupport not found — skipped (inactive account?)"
    fi

    rm -f "$tmp"
}

# Make Steam ignore the guide button: "Controller_CheckGuideButton" = 0
# (the GUI toggle "Guide button focuses Steam"). This key lives at the top
# level of UserLocalConfigStore (the whole file), where Steam appends it when
# the toggle is switched off. Insert it before the file's final closing brace.
patch_guide_off() {
    local file="$1"
    local tmp
    tmp="$(mktemp)"

    awk '
        BEGIN { found = 0; lastbrace = 0 }
        {
            line = $0
            if (line ~ /^[[:space:]]*"Controller_CheckGuideButton"/) {
                sub(/"[0-9]+"/, "\"0\"", line)
                found = 1
            }
            lines[NR] = line
            if (line ~ /^\}/) lastbrace = NR
        }
        END {
            for (i = 1; i <= NR; i++) {
                if (i == lastbrace && !found) print "\t\"Controller_CheckGuideButton\"\t\t\"0\""
                print lines[i]
            }
        }
    ' "$file" > "$tmp"

    if cmp -s "$tmp" "$file"; then
        echo "  $file: Controller_CheckGuideButton already 0"
    else
        cp "$file" "$file.bak"
        cp "$tmp" "$file"
        echo "  Patched $file: Controller_CheckGuideButton → 0 (guide button no longer focuses Steam)"
    fi

    rm -f "$tmp"
}

# Unbind the guide button from Steam's SDL gamepad mappings so Steam never
# sees it (the scripted equivalent of the GUI "Setup Device Inputs" wizard,
# where you skip the guide button). Steam logs the full runtime mapping for
# every controller it initializes:
#   "SDL Mapping for <vid>/<pid>: <runtime_guid>,<name>,a:b0,...,guide:b8,..."
# into <steam>/logs/controller.txt. We take the latest mapping per device,
# drop the guide binding, attach the device crc to the base GUID, and inject
# the result into config.vdf's SDL_GamepadBind — exactly what Steam writes
# when you skip the guide button in the wizard. With a non-empty $3 (vid/pid
# like 045e/028e) only that device is patched.
patch_guide_unbind() {
    local config="$1" logs="$2" device="${3:-}"
    if [ ! -f "$config" ]; then
        echo "  No config.vdf at $config — skipped"
        return 0
    fi
    if [ ! -d "$logs" ]; then
        echo "  No Steam logs at $logs — skipped"
        return 0
    fi

    local tmp mappings
    tmp="$(mktemp)"
    mappings="$(mktemp)"

    # Every logged mapping, newest first, one per device. The log uses CRLF
    # line endings, so strip the carriage returns. A device can show up under
    # several runtime GUIDs over time (the trailing bytes vary), so dedupe on
    # the vid/pid from the log header and keep the newest mapping — the one
    # Steam currently uses. The vid/pid prefix is kept so --device can filter.
    grep -h 'SDL Mapping for ' "$logs"/controller*.txt 2>/dev/null \
        | sed 's/.*SDL Mapping for \([0-9a-f]*\/[0-9a-f]*\): /\1 /' \
        | tr -d '\r' | tac | awk '!seen[$1]++ { print }' \
        > "$mappings"

    if [ ! -s "$mappings" ]; then
        echo "  No controller mappings in Steam logs — run Steam once with the controller connected."
        rm -f "$tmp" "$mappings"
        return 2
    fi

    if [ -n "$device" ]; then
        local tmp2
        tmp2="$(mktemp)"
        grep "^$device " "$mappings" > "$tmp2"
        rm -f "$mappings"
        mv "$tmp2" "$mappings"
        if [ ! -s "$mappings" ]; then
            echo "  No controller mappings for $device in Steam logs — connect the controller and run Steam once."
            rm -f "$tmp" "$mappings"
            return 2
        fi
    fi

    local injected=0 line runtime base crc name rest fields new
    while IFS= read -r line; do
        line="${line#* }"
        runtime="${line%%,*}"
        case "$runtime" in
            [0-9a-f]*) : ;;
            *) continue ;;
        esac
        [ "${#runtime}" -eq 32 ] || continue
        base="${runtime:0:4}0000${runtime:8}"
        crc="${runtime:6:2}${runtime:4:2}"
        rest="${line#*,}"
        name="${rest%%,*}"
        [ -n "$name" ] || continue
        [ "$name" = "*" ] && continue
        fields="${rest#*,}"
        fields=",$fields"
        fields="$(printf '%s' "$fields" | sed 's/,crc:[^,]*//g; s/,steam:[^,]*//g; s/,guide:[^,]*//g; s/,platform:[^,]*//g; s/^,//')"
        fields="${fields%,}"
        new="${base},${name},crc:${crc},platform:Linux,${fields},steam:2"

        # One entry per device (base GUID + name). Steam may have logged
        # several runtime GUIDs for the same device; all collapse onto the
        # first no-guide mapping for it, regardless of which crc that one has.
        if grep -Fq "${base},${name},crc:" "$config"; then
            echo "  $config: guide already unbound for $name"
            injected=1
            continue
        fi

        # SDL_GamepadBind's value is one multi-line string; each mapping is a
        # continuation line and the last one carries the closing quote. Insert
        # our mapping as a new continuation line right before it.
        if awk -v new="$new," -f /dev/stdin "$config" > "$tmp" <<'AWK'
            BEGIN { in_key = 0; injected = 0 }
            /^[[:space:]]*"SDL_GamepadBind"/ { print; in_key = 1; next }
            in_key {
                if ($0 ~ /"[[:space:]]*$/) {
                    print new
                    in_key = 0
                    injected = 1
                }
                print; next
            }
            { print }
            END { if (!injected) exit 1 }
AWK
        then
            cp "$config" "$config.bak"
            cp "$tmp" "$config"
            echo "  Patched $config: guide unbound for $name"
            injected=1
        else
            echo "  WARNING: SDL_GamepadBind not found in $config — $name guide left bound" >&2
        fi
    done < "$mappings"

    rm -f "$tmp" "$mappings"
    return 0
}

if [ -n "$DEVICE" ]; then
    # Per-device mode: unbind the guide button for this controller only, no
    # global keys, no per-appid patches. Used by bind-manager.sh after a bind.
    rc=0
    for dir in "${STEAM_DIRS[@]}"; do
        echo "Checking $dir/config/config.vdf"
        patch_guide_unbind "$dir/config/config.vdf" "$dir/logs" "$DEVKEY" || rc=$?
    done
    echo ""
    if [ "$rc" -eq 2 ]; then
        echo "WARNING: Steam has no SDL mapping for $DEVICE — the guide button is still bound."
        echo "Connect the controller and launch Steam once, then run:"
        echo "  $0 setup --device $DEVICE"
        exit 1
    fi
    echo "Done. The guide button is unbound from Steam's mapping for $DEVICE."
    echo "Restart Steam for it to take effect."
    exit 0
fi

for file in "${FILES[@]}"; do
    echo "Checking $file"
    for appid in "${APPIDS[@]}"; do
        patch_file "$file" "$appid"
    done
    if [ "$GLOBAL_OFF" -eq 1 ]; then
        patch_guide_off "$file"
        patch_global "$file"
    fi
done

if [ "$GLOBAL_OFF" -eq 1 ]; then
    for dir in "${STEAM_DIRS[@]}"; do
        echo "Checking $dir/config/config.vdf"
        patch_guide_unbind "$dir/config/config.vdf" "$dir/logs"
    done
fi

echo ""
if [ "$GLOBAL_OFF" -eq 1 ]; then
    echo "Done. The guide button will not focus Steam, and Xbox Configuration"
    echo "Support is off — Steam will ignore the pad. Restart Steam and launch"
    echo "the game; the guide button now triggers only your hss bind."
elif [ ${#APPIDS[@]} -gt 0 ]; then
    echo "Done. Start Steam and launch the game — Steam Input is now off for those"
    echo "titles, so the game reads the controller directly and the guide button"
    echo "will no longer open the Steam overlay."
fi
