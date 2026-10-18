import os
import sys
import json
import shutil
import subprocess
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PENDING_DIR = os.path.join(SCRIPT_DIR, "pending")
IN_PROGRESS_DIR = os.path.join(SCRIPT_DIR, "in_progress")
DONE_DIR = os.path.join(SCRIPT_DIR, "done")

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".m4v", ".wmv"}

CHANNEL_BITRATE_CEILING_KBPS = {1: 192, 2: 192, 6: 448, 8: 640}


def find_video_file(movie_dir):
    for file in sorted(os.listdir(movie_dir)):
        _, ext = os.path.splitext(file)
        if ext.lower() in VIDEO_EXTENSIONS and not file.startswith("original_"):
            return os.path.join(movie_dir, file)
    return None


def probe_media(video_path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries",
            "format=format_name,duration:stream=index,codec_name,codec_type,channels,bit_rate:stream_tags=language",
            "-of", "json",
            video_path,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def get_video_streams(probe_data):
    return [s for s in probe_data.get("streams", []) if s.get("codec_type") == "video"]


def get_audio_streams(probe_data):
    return [s for s in probe_data.get("streams", []) if s.get("codec_type") == "audio"]


def is_compliant(probe_data):
    format_name = probe_data.get("format", {}).get("format_name", "")
    if "mp4" not in format_name.split(","):
        return False
    video_streams = get_video_streams(probe_data)
    audio_streams = get_audio_streams(probe_data)
    if not video_streams or not audio_streams:
        return False
    return video_streams[0]["codec_name"] == "h264" and audio_streams[0]["codec_name"] == "aac"


def select_best_audio_stream(audio_streams):
    def quality_key(stream):
        bit_rate = int(stream["bit_rate"]) if stream.get("bit_rate") else 0
        channels = stream.get("channels") or 0
        return (bit_rate, channels)

    best = max(audio_streams, key=quality_key)
    if best.get("bit_rate"):
        reason = f"highest bit_rate ({int(best['bit_rate']) // 1000}kbps)"
    else:
        reason = f"no bit_rate reported, chose by channel count ({best.get('channels')} channels)"
    return best, reason


def compute_target_audio_bitrate_kbps(stream):
    channels = stream.get("channels") or 2
    ceiling = CHANNEL_BITRATE_CEILING_KBPS.get(channels, max(96 * channels, 96))
    if stream.get("bit_rate"):
        return min(int(stream["bit_rate"]) // 1000, ceiling)
    return ceiling


def build_ffmpeg_args(input_path, output_tmp_path, video_stream, best_audio):
    video_is_h264 = video_stream["codec_name"] == "h264"
    audio_is_aac = best_audio["codec_name"] == "aac"

    args = [
        "ffmpeg", "-y", "-i", input_path,
        "-map", f"0:{video_stream['index']}",
        "-map", f"0:{best_audio['index']}",
    ]

    if video_is_h264:
        args += ["-c:v", "copy"]
    else:
        args += ["-c:v", "libx264", "-preset", "slow", "-crf", "20"]

    if audio_is_aac:
        args += ["-c:a", "copy"]
    else:
        kbps = compute_target_audio_bitrate_kbps(best_audio)
        args += ["-c:a", "aac", "-b:a", f"{kbps}k"]

    args += ["-movflags", "+faststart", output_tmp_path]
    return args


def run_ffmpeg(args):
    result = subprocess.run(args, capture_output=True, text=True)
    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode == 0, output


def write_summary_log(movie_dir, lines):
    with open(os.path.join(movie_dir, "summary.log"), "a") as f:
        f.write("\n".join(lines) + "\n")


def describe_audio_stream(stream):
    lang = stream.get("tags", {}).get("language", "unknown")
    bit_rate = f"{int(stream['bit_rate']) // 1000}kbps" if stream.get("bit_rate") else "bitrate unknown"
    return f"[{stream['index']}] {stream['codec_name']}, {stream.get('channels')}ch, {bit_rate}, lang={lang}"


def transcode_movie(movie_dir, original_path, probe_data):
    video_streams = get_video_streams(probe_data)
    audio_streams = get_audio_streams(probe_data)
    video_stream = video_streams[0]
    best_audio, reason = select_best_audio_stream(audio_streams)

    base_name = os.path.basename(original_path)
    assert base_name.startswith("original_")
    output_name = os.path.splitext(base_name[len("original_"):])[0] + ".mp4"
    output_path = os.path.join(movie_dir, output_name)
    output_tmp_path = output_path + ".tmp.mp4"

    args = build_ffmpeg_args(original_path, output_tmp_path, video_stream, best_audio)

    log_lines = [
        f"=== Ingestion summary: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===",
        f"Source file: {base_name}",
        f"Source container: {probe_data.get('format', {}).get('format_name')}",
        f"Source video: {video_stream['codec_name']}",
        "Source audio tracks:",
    ]
    log_lines += [f"  {describe_audio_stream(s)}" for s in audio_streams]
    log_lines.append(f"Selected audio track: [{best_audio['index']}] ({reason})")
    log_lines.append("ffmpeg command:")
    log_lines.append(f"  {' '.join(args)}")

    success, output = run_ffmpeg(args)

    if success:
        os.rename(output_tmp_path, output_path)
        output_probe = probe_media(output_path)
        out_video = get_video_streams(output_probe)[0]
        out_audio = get_audio_streams(output_probe)[0]
        duration = output_probe.get("format", {}).get("duration", "unknown")
        log_lines.append("Result: SUCCESS")
        log_lines.append(f"Output file: {output_name}")
        log_lines.append(
            f"Output probe: video={out_video['codec_name']}, audio={out_audio['codec_name']}, duration={duration}s"
        )
        write_summary_log(movie_dir, log_lines)
        shutil.move(movie_dir, os.path.join(DONE_DIR, os.path.basename(movie_dir)))
        return True
    else:
        if os.path.exists(output_tmp_path):
            os.remove(output_tmp_path)
        tail = "\n".join(output.strip().splitlines()[-20:])
        log_lines.append(f"Result: FAILED (ffmpeg exit code != 0)")
        log_lines.append("ffmpeg output (tail):")
        log_lines.append(tail)
        write_summary_log(movie_dir, log_lines)
        return False


def process_pending_movie(movie_dir, position, total):
    name = os.path.basename(movie_dir)
    prefix = f"[{position}/{total}] {name}:"

    video_path = find_video_file(movie_dir)
    if video_path is None:
        print(f"{prefix} no video file found, skipping")
        return

    try:
        probe_data = probe_media(video_path)
    except subprocess.CalledProcessError as exc:
        print(f"{prefix} ffprobe failed, skipping ({exc})")
        return

    if is_compliant(probe_data):
        write_summary_log(movie_dir, [
            f"=== Ingestion summary: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===",
            f"Source file: {os.path.basename(video_path)}",
            "Already compliant (mp4/h264/aac) — moved without transcoding.",
        ])
        shutil.move(movie_dir, os.path.join(DONE_DIR, name))
        print(f"{prefix} already compliant, moved to done/")
        return

    print(f"{prefix} not compliant, transcoding...")

    new_movie_dir = os.path.join(IN_PROGRESS_DIR, name)
    shutil.move(movie_dir, new_movie_dir)

    original_path = os.path.join(new_movie_dir, "original_" + os.path.basename(video_path))
    os.rename(os.path.join(new_movie_dir, os.path.basename(video_path)), original_path)

    if transcode_movie(new_movie_dir, original_path, probe_data):
        print(f"{prefix} finished, moved to done/")
    else:
        print(f"{prefix} transcoding FAILED, left in in_progress/ (see summary.log)")


def resume_in_progress_movie(movie_dir, position, total):
    name = os.path.basename(movie_dir)
    prefix = f"[{position}/{total}] {name}:"

    original_path = None
    for file in os.listdir(movie_dir):
        if file.startswith("original_"):
            original_path = os.path.join(movie_dir, file)
            break

    if original_path is None:
        video_path = find_video_file(movie_dir)
        if video_path is None:
            print(f"{prefix} no video file found, skipping")
            return
        try:
            probe_data = probe_media(video_path)
        except subprocess.CalledProcessError as exc:
            print(f"{prefix} ffprobe failed, skipping ({exc})")
            return
        print(f"{prefix} resuming, transcoding...")
        original_path = os.path.join(movie_dir, "original_" + os.path.basename(video_path))
        os.rename(video_path, original_path)
        if transcode_movie(movie_dir, original_path, probe_data):
            print(f"{prefix} finished, moved to done/")
        else:
            print(f"{prefix} transcoding FAILED, left in in_progress/ (see summary.log)")
        return

    output_name = os.path.splitext(os.path.basename(original_path)[len("original_"):])[0] + ".mp4"
    output_path = os.path.join(movie_dir, output_name)
    if os.path.exists(output_path):
        shutil.move(movie_dir, os.path.join(DONE_DIR, name))
        print(f"{prefix} already moved to done/")
        return

    try:
        probe_data = probe_media(original_path)
    except subprocess.CalledProcessError as exc:
        print(f"{prefix} ffprobe failed, skipping ({exc})")
        return

    print(f"{prefix} resuming, transcoding...")
    if transcode_movie(movie_dir, original_path, probe_data):
        print(f"{prefix} finished, moved to done/")
    else:
        print(f"{prefix} transcoding FAILED, left in in_progress/ (see summary.log)")


def main():
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
        movie_dir = os.path.join(IN_PROGRESS_DIR, name)
        resume_in_progress_movie(movie_dir, position, total_in_progress)

    total_pending = len(pending_names)
    for position, name in enumerate(pending_names, start=1):
        movie_dir = os.path.join(PENDING_DIR, name)
        process_pending_movie(movie_dir, position, total_pending)

    print(f"Queue empty. {total_pending} movie(s) from pending/ processed this run.")


if __name__ == "__main__":
    main()
