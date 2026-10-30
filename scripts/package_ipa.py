"""Package an unsigned arm64 iPhoneOS .app for subsequent Windows re-signing.

This does NOT sign the app or make it directly installable on an iPhone.
"""
import argparse
import hashlib
import plistlib
from pathlib import Path
import struct
import zipfile


def validate_app(app: Path) -> None:
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Expected a built .app directory")
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Only a real-device iPhoneOS build can be packaged")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or "\\" in executable:
        raise ValueError("Invalid bundle executable name")
    binary = (app / executable).read_bytes()
    if len(binary) < 32:
        raise ValueError("Truncated executable")
    magic, cpu, _, _, commands, command_bytes, _, _ = struct.unpack_from("<8I", binary)
    if magic != 0xFEEDFACF or cpu != 0x0100000C:
        raise ValueError("Expected a thin arm64 Mach-O executable")
    if 32 + command_bytes > len(binary):
        raise ValueError("Truncated Mach-O load commands")
    offset = 32
    iphoneos = False
    for _ in range(commands):
        if offset + 8 > 32 + command_bytes:
            raise ValueError("Invalid load command header")
        command, size = struct.unpack_from("<2I", binary, offset)
        if size < 8 or offset + size > 32 + command_bytes:
            raise ValueError("Invalid load command size")
        if command == 0x32:  # LC_BUILD_VERSION; platform 2 = iOS, 7 = iOS Simulator
            if size < 24:
                raise ValueError("Invalid LC_BUILD_VERSION")
            iphoneos = struct.unpack_from("<I", binary, offset + 8)[0] == 2
        offset += size
    if not iphoneos:
        raise ValueError("Executable must target iOS, not the simulator")


def package(app: Path, output: Path) -> str:
    validate_app(app)
    files = sorted(path for path in app.rglob("*") if path.is_file())
    if any(path.is_symlink() for path in app.rglob("*")):
        raise ValueError("Symlinks are not supported by this minimal app packager")
    output = output.resolve()
    if app.resolve() in output.parents:
        raise ValueError("Output must not be inside the app bundle")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Never overwrite an existing artifact by accident.
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            relative = path.relative_to(app)
            if "_CodeSignature" in relative.parts or relative.name == "embedded.mobileprovision":
                continue
            archive.write(path, (Path("Payload") / app.name / relative).as_posix())
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".ipa.sha256").write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    return digest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(f"Unsigned IPA SHA256: {package(args.app, args.output)}")
