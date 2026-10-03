import os
import sys
import json
import subprocess
from collections import deque

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".m4v", ".wmv"}

def get_movies_in_library(library_path):
    movies = []
    for movie_title in os.listdir(library_path):
        movie_dir = os.path.join(library_path, movie_title)
        if os.path.isdir(movie_dir):
            movies.append(movie_dir)
    return movies

def probe_codecs(video_path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "stream=codec_name,codec_type",
            "-of", "json",
            str(video_path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    streams = json.loads(result.stdout).get("streams", [])
    has_h264 = any(s.get("codec_type") == "video" and s.get("codec_name") == "h264" for s in streams)
    has_aac = any(s.get("codec_type") == "audio" and s.get("codec_name") == "aac" for s in streams)
    return has_h264, has_aac

def analyze_movie(movie_dir):
    movie_details = {
        "name": os.path.split(movie_dir)[1],
        "ext": "",
        "has_h264": "no",
        "has_aac": "no",
        "has_subs": "no",
        "has_en": "no",
        "has_spa": "no",
    }
    
    # Analyze movie video file and parse codecs and extension
    for file in os.listdir(movie_dir):
        _, ext = os.path.splitext(file)
        if ext in VIDEO_EXTENSIONS:
            video_path = os.path.join(movie_dir, file)
            has_h264, has_aac = probe_codecs(video_path)
            movie_details["ext"] = ext
            movie_details["has_h264"] = "yes" if has_h264 else "no"
            movie_details["has_aac"] = "yes" if has_aac else "no"
            break

    # Return early if no supported video file was found
    if not movie_details["ext"]:
        return movie_details

    # Check subtitles
    for file in os.listdir(movie_dir):
        if file.endswith(".srt"):
            movie_details["has_subs"] = "yes"
        if file.endswith(".en.srt"):
            movie_details["has_en"] = "yes"
        if file.endswith(".spa.srt"):
            movie_details["has_spa"] = "yes"
    
    return movie_details

def print_row(movie_details):
    def column(value, length):
        buffer = [" "] * length
        for i in range(min(len(value), length)):
            buffer[i] = value[i]
        return "".join(buffer)

    columns = deque([
        column(movie_details["name"], 45),
        column(movie_details["ext"], 4),
        column(movie_details["has_h264"], 10),
        column(movie_details["has_aac"], 9),
        column(movie_details["has_subs"], 8),
        column(movie_details["has_en"], 12),
        column(movie_details["has_spa"], 12),
    ])

    row = ["| "]
    while columns:
        row.append(columns.popleft())
        row.append(" | " if columns else " |")

    print("".join(row))

def analyze_and_report(movies):
    missing_video = []
    print("| Name                                          | Ext  | H264 video | AAC audio | Has subs | English subs | Spanish subs |")
    print("|-----------------------------------------------|------|------------|-----------|----------|--------------|--------------|")
    for movie_dir in movies:
        movie_details = analyze_movie(movie_dir)
        if movie_details["ext"]:
            print_row(movie_details)
        else:
            missing_video.append(movie_details["name"])

    print("\nNo video files found for the following movies:")
    for movie in missing_video:
        print(f" {movie}")
    
def main():
    if len(sys.argv) < 2:
        print("No path provided...")
        return

    movies_path = sys.argv[1]

    if not os.path.exists(movies_path) or not os.path.isdir(movies_path):
        print("Provided path does not exist or is not a directory")
        return

    movies = get_movies_in_library(movies_path)

    if len(movies) == 0:
        return f"No movies were found in path ${movies_path}"

    analyze_and_report(movies)

if __name__=="__main__":
    main()