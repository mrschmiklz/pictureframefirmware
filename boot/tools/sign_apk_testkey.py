#!/usr/bin/env python3
"""Sign an APK with the public AOSP testkey (eng/test-keys builds)."""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
TESTKEY_URL = "https://raw.githubusercontent.com/aosp-mirror/platform_build/master/target/product/security/testkey.x509.pem"
TESTKEY_PK8_URL = "https://raw.githubusercontent.com/aosp-mirror/platform_build/master/target/product/security/testkey.pk8"


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {dest.name} ...")
    urllib.request.urlretrieve(url, dest)


def zipalign_apk(input_apk: Path, output_apk: Path) -> None:
    with zipfile.ZipFile(input_apk, "r") as src, zipfile.ZipFile(output_apk, "w") as dst:
        for info in src.infolist():
            data = src.read(info.filename)
            dst.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)


def find_jarsigner() -> str:
    candidates = [
        Path(r"C:\Program Files\Java\jdk-23\bin\jarsigner.exe"),
        Path(r"C:\Program Files\Java\jdk-21\bin\jarsigner.exe"),
        Path(r"C:\Program Files\Java\jdk-17\bin\jarsigner.exe"),
    ]
    for path in candidates:
        if path.exists():
            return str(path)
    from shutil import which

    found = which("jarsigner")
    if found:
        return found
    raise RuntimeError("jarsigner not found; install a JDK")


def sign_apk(unsigned_apk: Path, signed_apk: Path) -> None:
    cert = TOOLS / "testkey.x509.pem"
    key = TOOLS / "testkey.pk8"
    p12 = TOOLS / "testkey.p12"
    download(TESTKEY_URL, cert)
    download(TESTKEY_PK8_URL, key)

    if not p12.exists():
        print("Creating testkey PKCS12 keystore ...")
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.serialization import pkcs12
        from cryptography import x509
        from cryptography.hazmat.backends import default_backend

        private_key = serialization.load_der_private_key(
            key.read_bytes(), password=None, backend=default_backend()
        )
        certificate = x509.load_pem_x509_certificate(
            cert.read_bytes(), backend=default_backend()
        )
        p12.write_bytes(
            pkcs12.serialize_key_and_certificates(
                b"testkey",
                private_key,
                certificate,
                None,
                serialization.BestAvailableEncryption(b"android"),
            )
        )

    jarsigner = find_jarsigner()
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        aligned = tmp_path / "aligned.apk"
        zipalign_apk(unsigned_apk, aligned)
        aligned_signed = tmp_path / "signed.apk"
        cmd = [
            jarsigner,
            "-storetype",
            "PKCS12",
            "-keystore",
            str(p12),
            "-storepass",
            "android",
            "-keypass",
            "android",
            "-signedjar",
            str(aligned_signed),
            str(aligned),
            "testkey",
        ]
        print("Signing APK with AOSP testkey ...")
        subprocess.run(cmd, check=True)
        aligned_signed.replace(signed_apk)


def main() -> None:
    parser = argparse.ArgumentParser(description="Sign patched Aimor APK")
    parser.add_argument("input_apk")
    parser.add_argument("output_apk")
    args = parser.parse_args()
    sign_apk(Path(args.input_apk), Path(args.output_apk))
    print(f"Signed -> {args.output_apk}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode)
