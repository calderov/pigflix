import argparse
import os
import re
import sys
import shutil
import subprocess
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PENDING_DIR = os.path.join(SCRIPT_DIR, "pending")
IN_PROGRESS_DIR = os.path.join(SCRIPT_DIR, "in_progress")
DONE_DIR = os.path.join(SCRIPT_DIR, "done")

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".m4v", ".wmv"}
SYNC_THRESHOLD_SECONDS = 0.5

TIMESTAMP_RE = re.compile(r"(\d\d):(\d\d):(\d\d),(\d\d\d) --> ")


def parse_start_times(srt_path):
    with open(srt_path, encoding="utf-8", errors="ignore") as f:
        text = f.read()
    times = []
    for h, m, s, ms in TIMESTAMP_RE.findall(text):
        times.append(((int(h) * 60 + int(m)) * 60 + int(s)) + int(ms) / 1000)
    return times


def compute_shift_seconds(original_path, synced_path):
    original_times = parse_start_times(original_path)
    synced_times = parse_start_times(synced_path)
    if not original_times or not synced_times:
        return None
    first_diff = abs(synced_times[0] - original_times[0])
    last_diff = abs(synced_times[-1] - original_times[-1])
    return max(first_diff, last_diff)


def find_video_file(movie_dir):
    for file in sorted(os.listdir(movie_dir)):
        _, ext = os.path.splitext(file)
        if ext.lower() in VIDEO_EXTENSIONS:
            return os.path.join(movie_dir, file)
    return None


def find_srt_files(movie_dir):
    return sorted(f for f in os.listdir(movie_dir) if f.lower().endswith(".srt"))


def ffs_executable():
    return os.path.join(os.path.dirname(sys.executable), "ffs")


def check_and_sync_subtitle(movie_dir, video_path, srt_filename, auto_yes=False):
    srt_path = os.path.join(movie_dir, srt_filename)
    stem, ext = os.path.splitext(srt_path)
    tmp_path = f"{stem}.synced{ext}"

    try:
        result = subprocess.run(
            [ffs_executable(), video_path, "-i", srt_path, "-o", tmp_path],
            capture_output=True, text=True, timeout=900,
        )
    except subprocess.TimeoutExpired:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        return [f"{srt_filename}: sync check timed out, left unchanged"]

    if result.returncode != 0 or not os.path.exists(tmp_path):
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        tail = "\n".join((result.stderr or result.stdout or "").strip().splitlines()[-10:])
        return [f"{srt_filename}: sync check failed, left unchanged:\n  {tail}"]

    shift = compute_shift_seconds(srt_path, tmp_path)
    if shift is None or shift < SYNC_THRESHOLD_SECONDS:
        os.remove(tmp_path)
        return [f"{srt_filename}: already in sync"]

    if auto_yes:
        answer = "y"
    else:
        answer = input(f"  '{srt_filename}' looks out of sync (~{shift:.1f}s). Attempt auto-sync? [y/N]: ").strip().lower()
    if answer != "y":
        os.remove(tmp_path)
        return [f"{srt_filename}: out of sync, user declined auto-sync, left unchanged"]

    backup_path = os.path.join(movie_dir, f"{srt_filename}.original")
    shutil.move(srt_path, backup_path)
    os.replace(tmp_path, srt_path)
    return [f"{srt_filename}: out of sync, auto-synced (backup saved as {srt_filename}.original)"]


def write_summary_log(movie_dir, lines):
    with open(os.path.join(movie_dir, "summary.log"), "a") as f:
        f.write("\n".join(lines) + "\n")


def process_movie(movie_dir, position, total, auto_yes=False):
    name = os.path.basename(movie_dir)
    prefix = f"[{position}/{total}] {name}:"

    video_path = find_video_file(movie_dir)
    if video_path is None:
        print(f"{prefix} no video file found, skipping")
        return

    log_lines = [f"=== Subtitle sync summary: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ==="]

    srt_files = find_srt_files(movie_dir)
    if not srt_files:
        log_lines.append("No subtitle files found, nothing to sync")
        print(f"{prefix} no subtitle files found, nothing to sync")
    else:
        print(f"{prefix} checking {len(srt_files)} subtitle file(s)...")
        for srt_filename in srt_files:
            result = check_and_sync_subtitle(movie_dir, video_path, srt_filename, auto_yes=auto_yes)
            log_lines.extend(result)
            print(f"{prefix} {result[0]}")

    write_summary_log(movie_dir, log_lines)
    shutil.move(movie_dir, os.path.join(DONE_DIR, name))
    print(f"{prefix} finished, moved to done/")


def main():
    parser = argparse.ArgumentParser(
        description="Check and sync subtitle files for movies in pending/."
    )
    parser.add_argument(
        "-y", "--yes",
        action="store_true",
        help="Don't ask for confirmation before syncing an out-of-sync subtitle; proceed automatically.",
    )
    args = parser.parse_args()

    os.makedirs(PENDING_DIR, exist_ok=True)
    os.makedirs(IN_PROGRESS_DIR, exist_ok=True)
    os.makedirs(DONE_DIR, exist_ok=True)

    in_progress_names = [n for n in sorted(os.listdir(IN_PROGRESS_DIR)) if os.path.isdir(os.path.join(IN_PROGRESS_DIR, n))]
    pending_names = [n for n in sorted(os.listdir(PENDING_DIR)) if os.path.isdir(os.path.join(PENDING_DIR, n))]

    print(f"Found {len(pending_names)} movie(s) in pending/")
    if in_progress_names:
        print(f"Found {len(in_progress_names)} movie(s) left over in in_progress/ from a previous run, resuming...")

    total_in_progress = len(in_progress_names)
    for position, name in enumerate(in_progress_names, start=1):
        process_movie(os.path.join(IN_PROGRESS_DIR, name), position, total_in_progress, auto_yes=args.yes)

    total_pending = len(pending_names)
    for position, name in enumerate(pending_names, start=1):
        src = os.path.join(PENDING_DIR, name)
        dest = os.path.join(IN_PROGRESS_DIR, name)
        shutil.move(src, dest)
        process_movie(dest, position, total_pending, auto_yes=args.yes)

    print(f"Queue empty. {total_pending} movie(s) from pending/ processed this run.")


if __name__ == "__main__":
    main()
