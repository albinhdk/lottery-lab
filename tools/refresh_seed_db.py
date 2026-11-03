#!/usr/bin/env python3
"""Refresh `frontend/assets/lottery.db`, the database bundled into the APK.

The mobile app copies this file into its private storage on first launch, so
the app has full history without a network round-trip. Run this after syncing
new draws (`POST /api/sync` on the desktop backend), then rebuild the APK.
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "backend" / "data" / "lottery.db"
TARGET = ROOT / "frontend" / "assets" / "lottery.db"
MANIFEST = ROOT / "frontend" / "assets" / "lottery_seed.json"


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"找不到 {SOURCE}，请先启动后端并同步数据。")

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    if TARGET.exists():
        TARGET.unlink()

    src = sqlite3.connect(f"file:{SOURCE.as_posix()}?mode=ro", uri=True)
    dst = sqlite3.connect(TARGET)
    try:
        src.backup(dst)
        dst.execute("PRAGMA journal_mode=DELETE")
        dst.commit()
        counts = {
            game: {"count": count, "first": first, "last": last}
            for game, count, first, last in dst.execute(
                "SELECT game, COUNT(*), MIN(draw_date), MAX(draw_date) "
                "FROM draws GROUP BY game ORDER BY game"
            )
        }
        size = TARGET.stat().st_size
    finally:
        dst.close()
        src.close()

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "size": size,
        "games": counts,
    }
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"已写入 {TARGET.relative_to(ROOT)}（{size / 1024:.0f} KB）")
    for game, info in counts.items():
        print(f"  {game}: {info['count']} 期，{info['first']} ~ {info['last']}")
    print(f"清单：{MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
