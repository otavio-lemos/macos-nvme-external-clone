#!/bin/sh
set -e
if [ -f "/Volumes/Macintosh HD - Data/private/var/db/eligibilityd/eligibility.plist" ]; then
  TARGET="/Volumes/Macintosh HD - Data"
elif [ -f "/private/var/db/eligibilityd/eligibility.plist" ]; then
  TARGET=""
else
  echo "ERRO: Volume 'Macintosh HD - Data' nao encontrado em /Volumes."
  exit 1
fi

PB="/usr/libexec/PlistBuddy"
[ -x "$PB" ] || PB="/Volumes/Macintosh HD/usr/libexec/PlistBuddy"
CF="/usr/bin/chflags"
[ -x "$CF" ] || CF="/Volumes/Macintosh HD/usr/bin/chflags"

P1="$TARGET/private/var/db/eligibilityd/eligibility.plist"
P2="$TARGET/private/var/db/os_eligibility/eligibility.plist"

"$CF" nouchg "$P1" "$P2" 2>/dev/null || true
cp -p "$P1" "$P1.bak" 2>/dev/null || true
cp -p "$P2" "$P2.bak" 2>/dev/null || true

"$PB" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_GREYMATTER:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_GREYMATTER:os_eligibility_answer_t 4" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_AMERICIUM:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_AMERICIUM:os_eligibility_answer_t 4" \
  "$P1"

"$PB" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SIRI_MODE:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SIRI_MODE:os_eligibility_answer_t 4" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_XCODE_LLM:os_eligibility_answer_t 4" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:status:OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE 3" \
  -c "Set :OS_ELIGIBILITY_DOMAIN_SWIFT_ASSIST:os_eligibility_answer_t 4" \
  "$P2"

"$CF" uchg "$P1" "$P2"
echo "OK! Siri AI / Apple Intelligence liberado em: ${TARGET:-/}"
