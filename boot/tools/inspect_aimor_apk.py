#!/usr/bin/env python3
import re
import zipfile
from pathlib import Path

APK = Path(__file__).resolve().parents[2] / "dump" / "launcher_aimor.apk"


def main() -> None:
    with zipfile.ZipFile(APK) as zf:
        for name in sorted(zf.namelist()):
            if not name.startswith("res/") or not name.endswith(".xml"):
                continue
            data = zf.read(name)
            low = data.lower()
            if not any(k in low for k in (b"welcome", b"count", b"logo", b"loading", b"splash")):
                continue
            text = data.decode("utf-8", "ignore")
            ids = re.findall(r"@\+id/[A-Za-z0-9_]+", text)
            if ids:
                print(f"=== {name} ===")
                for item in sorted(set(ids)):
                    print(f"  {item}")

        print("\n=== SETTINGS / boot related strings in dex/assets ===")
        blob = b"".join(
            zf.read(n)
            for n in zf.namelist()
            if n.endswith(".dex") or n.startswith("assets/")
        )
        for pat in (
            b"welcome_[a-z_]+",
            b"boot_[a-z_]+",
            b"start_[a-z_]+",
            b"[a-z_]*countdown[a-z_]*",
            b"CountDownTimer",
            b"image_view_logo_[a-z_]+",
            b"loading_[a-z_]+",
            b"show_welcome",
            b"guide_[a-z_]+",
        ):
            hits = sorted({m.group().decode("ascii", "ignore") for m in re.finditer(pat, blob, re.I)})
            if hits:
                print(f"\n{pat.decode()}:")
                for hit in hits[:20]:
                    print(f"  {hit}")


if __name__ == "__main__":
    main()
