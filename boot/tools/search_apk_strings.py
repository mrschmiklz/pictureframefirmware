#!/usr/bin/env python3
import re
import sys
import zipfile

apk = sys.argv[1]
with zipfile.ZipFile(apk) as zf:
    blob = b"".join(zf.read(name) for name in zf.namelist())

patterns = [
    rb"/sdcard[\w./-]{0,80}",
    rb"/storage/emulated[\w./-]{0,80}",
    rb"start_up_time",
    rb"is_show_guide",
    rb"icon_aimor_logo[\w_]*",
    rb"icon_guide_bg",
    rb"layer_auth_reboot_bg",
    rb"tv_count_down",
    rb"welcome_title",
]

for pat in patterns:
    hits = sorted({m.group().decode("ascii", "ignore") for m in re.finditer(pat, blob, re.I)})
    if hits:
        print(f"=== {pat.decode(errors='ignore')} ===")
        for hit in hits:
            print(f"  {hit}")
