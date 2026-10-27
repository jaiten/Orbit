"""Preserve tracked iOS input timestamps so restored Xcode builds can be incremental.

Run on a clean checkout with full Git history, before XcodeGen. File content is never
changed. Dirty checkouts are rejected so local edits cannot be hidden from Xcode.
"""
from pathlib import Path
import os
import subprocess


def restore(root: Path) -> int:
    def git(*args: str) -> bytes:
        return subprocess.check_output(["git", "-C", str(root), *args])

    if git("status", "--porcelain", "--untracked-files=no", "--", "ios", "shared").strip():
        raise RuntimeError("Restore source timestamps only on a clean iOS/shared checkout")
    if git("rev-parse", "--is-shallow-repository").strip() == b"true":
        raise RuntimeError("Full Git history is required (checkout fetch-depth: 0)")
    restored = 0
    for entry in git("ls-files", "-z", "--", "ios", "shared").split(b"\0"):
        if not entry:
            continue
        relative = os.fsdecode(entry)
        file = root / relative
        if not file.is_file() or file.is_symlink():
            continue
        timestamp = git("log", "-1", "--format=%ct", "--", relative).strip()
        if timestamp:
            epoch = int(timestamp)
            os.utime(file, (epoch, epoch))
            restored += 1
    return restored


if __name__ == "__main__":
    count = restore(Path(__file__).resolve().parents[1])
    print(f"Restored timestamps for {count} tracked iOS/shared inputs")
