#!/bin/sh
set -e

REP_DIR="$HOME/Library/Group Containers/group.com.apple.replicatord/replicatord"
PREF_FILE="$HOME/Library/Containers/com.apple.ScreenContinuity/Data/Library/Preferences/com.apple.ScreenContinuity.plist"
STAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$REP_DIR/backup_$STAMP"

mkdir -p "$BACKUP_DIR"

for f in "$REP_DIR"/replicatord.sql*; do
  if [ -e "$f" ]; then
    cp -p "$f" "$BACKUP_DIR/"
    rm -f "$f"
  fi
done

if [ -e "$PREF_FILE" ]; then
  cp -p "$PREF_FILE" "$BACKUP_DIR/"
  rm -f "$PREF_FILE"
fi

for proc in replicatord sharingd rapportd ContinuityCaptureAgent; do
  killall "$proc" 2>/dev/null || true
done

echo "OK! Cache do replicatord/ScreenContinuity limpo (backup em: $BACKUP_DIR)."
echo "Abra o Espelhamento do iPhone para concluir o novo pareamento."
