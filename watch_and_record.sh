#!/bin/bash
trap '' SIGINT
UNAME="$1"
TG_FLAG="$2"
INTERVAL="$3"
SCHEDULE="$4"
DELAY_HOURS="$5"
cd "$(dirname "$0")" || exit 1

while true; do
    live=$(uv run python check_live_status.py "$UNAME" 2>/dev/null | tail -1)
    if [ "$live" = "LIVE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $UNAME dang live, bat dau ghi (gioi han ${SCHEDULE} phut)..."
        uv run python src/main.py -user "$UNAME" -output ~/recordings $TG_FLAG -duration $((SCHEDULE*60)) -no-update-check
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Da ghi xong. Cho ${DELAY_HOURS} gio truoc khi kiem tra lai $UNAME..."
        sleep $((DELAY_HOURS*3600))
    else
        sleep $((INTERVAL*60))
    fi
done
