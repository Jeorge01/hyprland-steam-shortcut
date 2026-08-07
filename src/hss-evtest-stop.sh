#!/bin/bash
# hss-evtest-stop — kill evtest listeners attached to the given input event
# nodes, or (with --holders) list the processes holding them open. Runs as
# root via sudo (NOPASSWD). The bind listener runs evtest as root inside a
# user systemd service, whose cgroup the user manager cannot kill, so stopping
# a bind needs this explicit, scoped kill.
#
# HSS_EVTEST_STOP_VERSION is the feature contract consumed by steam-trigger.sh:
# version >= 1 guarantees --holders support. install.sh checks for the constant
# to fail loudly on a corrupted download.
HSS_EVTEST_STOP_VERSION=1

if [ "$1" = "--holders" ]; then
    shift
    for node in "$@"; do
        case "$node" in
            event[0-9]*) ;;
            *) continue ;;
        esac
        fuser -v "/dev/input/$node"
    done
    exit 0
fi
for node in "$@"; do
    case "$node" in
        event[0-9]*) ;;
        *) continue ;;
    esac
    pkill -f "evtest /dev/input/$node" 2>/dev/null
done
exit 0
