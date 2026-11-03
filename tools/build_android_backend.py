#!/usr/bin/env python3
"""Build the Rust backend as an Android shared library and copy it into
`frontend/android/app/src/main/jniLibs/`.

Usage:
    python tools/build_android_backend.py                 # all ABIs
    python tools/build_android_backend.py arm64-v8a       # one ABI

The Android NDK is located from ANDROID_NDK_HOME / ANDROID_NDK_ROOT, or from
`frontend/android/local.properties` (sdk.dir), or the default Windows SDK path.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
JNI_LIBS = ROOT / "frontend" / "android" / "app" / "src" / "main" / "jniLibs"

API_LEVEL = 24
ABIS = {
    "arm64-v8a": ("aarch64-linux-android", "aarch64-linux-android"),
    "armeabi-v7a": ("armv7-linux-androideabi", "armv7a-linux-androideabi"),
    "x86_64": ("x86_64-linux-android", "x86_64-linux-android"),
}


def find_ndk() -> Path:
    for key in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        value = os.environ.get(key)
        if value and Path(value).is_dir():
            return Path(value)

    sdk: Path | None = None
    local_props = ROOT / "frontend" / "android" / "local.properties"
    if local_props.exists():
        for line in local_props.read_text(encoding="utf-8").splitlines():
            if line.startswith("sdk.dir="):
                sdk = Path(line.split("=", 1)[1].replace("\\\\", "\\").replace("\\:", ":"))
                break
    if sdk is None:
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            sdk = Path(local_app_data) / "Android" / "Sdk"
    if sdk is None or not (sdk / "ndk").is_dir():
        sys.exit("找不到 Android NDK，请设置 ANDROID_NDK_HOME。")

    candidates = sorted((sdk / "ndk").iterdir(), key=lambda p: p.name)
    if not candidates:
        sys.exit(f"{sdk / 'ndk'} 下没有已安装的 NDK 版本。")
    return candidates[-1]


def build(abi: str, ndk: Path) -> None:
    target, clang_prefix = ABIS[abi]
    toolchain = ndk / "toolchains" / "llvm" / "prebuilt" / "windows-x86_64" / "bin"
    if not toolchain.is_dir():
        # Non-Windows host.
        toolchain = ndk / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64" / "bin"
    if not toolchain.is_dir():
        sys.exit(f"找不到 NDK 工具链：{toolchain}")

    suffix = ".cmd" if os.name == "nt" else ""
    clang = toolchain / f"{clang_prefix}{API_LEVEL}-clang{suffix}"
    llvm_ar = toolchain / ("llvm-ar.exe" if os.name == "nt" else "llvm-ar")
    if not clang.exists():
        sys.exit(f"找不到编译器：{clang}")

    env = os.environ.copy()
    env[f"CC_{target}"] = str(clang)
    env[f"CC_{target.replace('-', '_')}"] = str(clang)
    env[f"AR_{target}"] = str(llvm_ar)
    env[f"AR_{target.replace('-', '_')}"] = str(llvm_ar)
    env[f"CARGO_TARGET_{target.upper().replace('-', '_')}_LINKER"] = str(clang)
    env["ANDROID_NDK_HOME"] = str(ndk)
    env["ANDROID_NDK_ROOT"] = str(ndk)
    env["CMAKE_TOOLCHAIN_FILE"] = str(ndk / "build" / "cmake" / "android.toolchain.cmake")
    env["ANDROID_ABI"] = abi
    env["ANDROID_PLATFORM"] = f"android-{API_LEVEL}"

    print(f"[{abi}] cargo build --target {target} …")
    subprocess.run(
        ["cargo", "build", "--release", "--lib", "--target", target],
        cwd=BACKEND,
        env=env,
        check=True,
    )

    src = BACKEND / "target" / target / "release" / "liblottery_lab_backend.so"
    if not src.exists():
        sys.exit(f"构建产物不存在：{src}")
    dst = JNI_LIBS / abi / "liblottery_lab_backend.so"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"[{abi}] {src.name} -> {dst.relative_to(ROOT)} ({src.stat().st_size / 1024 / 1024:.1f} MB)")


def main() -> None:
    requested = sys.argv[1:] or list(ABIS)
    unknown = [abi for abi in requested if abi not in ABIS]
    if unknown:
        sys.exit(f"未知 ABI：{', '.join(unknown)}（可选：{', '.join(ABIS)}）")
    ndk = find_ndk()
    print(f"NDK: {ndk}")
    for abi in requested:
        build(abi, ndk)


if __name__ == "__main__":
    main()
