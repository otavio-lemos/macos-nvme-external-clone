#!/usr/bin/env python3
"""Unlock Siri AI / Apple Intelligence external boot eligibility plists."""

import os
import plistlib
import shutil
import subprocess

ELIGIBILITY_PLISTS = (
    "/private/var/db/eligibilityd/eligibility.plist",
    "/private/var/db/os_eligibility/eligibility.plist",
)


def patch_plist(path: str) -> None:
    """Update external boot eligibility inputs and lock the plist file."""
    subprocess.run(["chflags", "nouchg", path], check=False)
    backup_path = path + ".bak"
    if not os.path.exists(backup_path):
        shutil.copy2(path, backup_path)

    with open(path, "rb") as f:
        data = plistlib.load(f)

    for entry in data.values():
        if not isinstance(entry, dict):
            continue
        status = entry.get("status")
        if isinstance(status, dict) and "OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE" in status:
            status["OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE"] = 3
            entry["os_eligibility_answer_t"] = 4

    with open(path, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML)

    subprocess.run(["chflags", "uchg", path], check=True)


def main() -> None:
    """Patch both eligibility plists and restart affected daemons."""
    for path in ELIGIBILITY_PLISTS:
        patch_plist(path)

    for proc in ("eligibilityd", "generativeexperiencesd", "modelcatalogd", "Siri AI"):
        subprocess.run(["killall", proc], check=False)

    print("OK! Siri AI liberado no NVMe externo.")


if __name__ == "__main__":
    main()
