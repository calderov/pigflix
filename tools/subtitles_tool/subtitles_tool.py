import os
import re
import io
import sys
import time
import base64
import zipfile
import shutil
import subprocess
from datetime import datetime

import requests
from bs4 import BeautifulSoup

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PENDING_DIR = os.path.join(SCRIPT_DIR, "pending")
IN_PROGRESS_DIR = os.path.join(SCRIPT_DIR, "in_progress")
DONE_DIR = os.path.join(SCRIPT_DIR, "done")
ENV_FILE_PATH = os.path.join(SCRIPT_DIR, ".env")
TRANSLATE_SCRIPT_PATH = os.path.join(SCRIPT_DIR, "translate_subs.py")

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".m4v", ".wmv"}

TMDB_BASE = "https://api.themoviedb.org/3"
YTS_SUBS_BASE = "https://yts-subs.com"
REQUEST_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; pigflix-subtitles-tool/1.0)"}
LANGUAGES = [("en", "English"), ("spa", "Spanish")]
YTS_SUBS_REQUEST_DELAY_SECONDS = 1


def find_video_file(movie_dir):
    for file in sorted(os.listdir(movie_dir)):
        _, ext = os.path.splitext(file)
        if ext.lower() in VIDEO_EXTENSIONS:
            return os.path.join(movie_dir, file)
    return None


def parse_title_and_year(filename):
    base = os.path.splitext(os.path.basename(filename))[0]
    cleaned = base.replace(".", " ").replace("_", " ")

    year = None
    year_match = re.search(r"\b(19\d{2}|20\d{2})\b", cleaned)
    if year_match:
        year = int(year_match.group(1))
        cleaned = cleaned[:year_match.start()]

    cleaned = re.sub(r"[\[\](){}]", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()

    return (cleaned or base), year


def get_env_value(name):
    value = os.environ.get(name)
    if value:
        return value
    if os.path.exists(ENV_FILE_PATH):
        with open(ENV_FILE_PATH) as f:
            for line in f:
                line = line.strip()
                if line.startswith(f"{name}="):
                    v = line.split("=", 1)[1].strip()
                    if v:
                        return v
    return None


def get_tmdb_api_key():
    return get_env_value("TMDB_API_KEY")


def tmdb_search_movie(title, year, api_key):
    params = {"api_key": api_key, "query": title}
    if year:
        params["year"] = year
    try:
        resp = requests.get(f"{TMDB_BASE}/search/movie", params=params, timeout=10)
        resp.raise_for_status()
        results = resp.json().get("results") or []
        return results[0] if results else None
    except requests.RequestException:
        return None


def tmdb_get_imdb_id(tmdb_movie_id, api_key):
    try:
        resp = requests.get(
            f"{TMDB_BASE}/movie/{tmdb_movie_id}/external_ids",
            params={"api_key": api_key},
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json().get("imdb_id") or None
    except requests.RequestException:
        return None


def fetch_movie_page(imdb_id):
    try:
        resp = requests.get(f"{YTS_SUBS_BASE}/movie-imdb/{imdb_id}", headers=REQUEST_HEADERS, timeout=10)
        if resp.status_code == 404:
            return None, "not found on yts-subs"
        resp.raise_for_status()
        return BeautifulSoup(resp.text, "html.parser"), None
    except requests.RequestException as exc:
        return None, f"network error ({exc})"


def find_best_subtitle_row(soup, language_name):
    best_href = None
    best_rating = None
    for row in soup.select("tr[data-id]"):
        lang_span = row.select_one("span.sub-lang")
        if not lang_span or lang_span.get_text(strip=True) != language_name:
            continue
        rating_span = row.select_one("td.rating-cell span.label")
        rating_text = rating_span.get_text(strip=True) if rating_span else ""
        rating = int(rating_text) if rating_text.isdigit() else 0
        link = row.select_one("td.download-cell a.subtitle-download")
        if not link or not link.get("href"):
            continue
        if best_rating is None or rating > best_rating:
            best_rating = rating
            best_href = link["href"]
    return best_href


def fetch_detail_page_download_url(detail_href):
    detail_url = YTS_SUBS_BASE + detail_href
    try:
        resp = requests.get(detail_url, headers=REQUEST_HEADERS, timeout=10)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        btn = soup.select_one("a#btn-download-subtitle")
        if not btn or not btn.get("data-link"):
            return None, detail_url
        return base64.b64decode(btn["data-link"]).decode(), detail_url
    except (requests.RequestException, ValueError):
        return None, detail_url


def fetch_subtitle_zip(zip_url, referer):
    try:
        headers = dict(REQUEST_HEADERS)
        headers["Referer"] = referer
        resp = requests.get(zip_url, headers=headers, timeout=20)
        resp.raise_for_status()
        return resp.content
    except requests.RequestException:
        return None


def extract_srt_from_zip(zip_bytes):
    try:
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
            names = [n for n in zf.namelist() if n.lower().endswith(".srt")]
            return zf.read(names[0]) if names else None
    except zipfile.BadZipFile:
        return None


def ensure_subtitle(movie_dir, video_stem, lang_code, lang_name, imdb_id, movie_soup):
    srt_path = os.path.join(movie_dir, f"{video_stem}.{lang_code}.srt")
    if os.path.exists(srt_path):
        return [f"{lang_name}: already present ({os.path.basename(srt_path)})"]

    if movie_soup is None:
        reason = "no imdb_id available" if not imdb_id else f"yts-subs unavailable for imdb_id={imdb_id}"
        return [f"{lang_name}: MISSING, not fetched ({reason})"]

    detail_href = find_best_subtitle_row(movie_soup, lang_name)
    if not detail_href:
        return [f"{lang_name}: MISSING, not fetched ({lang_name} not available on yts-subs for imdb_id={imdb_id})"]

    time.sleep(YTS_SUBS_REQUEST_DELAY_SECONDS)
    zip_url, detail_url = fetch_detail_page_download_url(detail_href)
    if not zip_url:
        return [f"{lang_name}: MISSING, not fetched (could not resolve download link at {detail_url})"]

    time.sleep(YTS_SUBS_REQUEST_DELAY_SECONDS)
    zip_bytes = fetch_subtitle_zip(zip_url, detail_url)
    if not zip_bytes:
        return [f"{lang_name}: MISSING, not fetched (zip download failed from {detail_url})"]

    srt_bytes = extract_srt_from_zip(zip_bytes)
    if not srt_bytes:
        return [f"{lang_name}: MISSING, not fetched (zip at {detail_url} had no .srt member)"]

    with open(srt_path, "wb") as f:
        f.write(srt_bytes)
    return [f"{lang_name}: FETCHED from {detail_url} (imdb_id={imdb_id}) -> {os.path.basename(srt_path)}"]


def translate_missing_subtitle(movie_dir, video_stem, source_code, source_name,
                                target_code, target_name, openai_api_key):
    if not openai_api_key:
        return [f"{target_name}: MISSING, not fetched and OPENAI_API_KEY not set, cannot translate from {source_name}"]

    source_path = os.path.join(movie_dir, f"{video_stem}.{source_code}.srt")
    target_path = os.path.join(movie_dir, f"{video_stem}.{target_code}.srt")

    try:
        result = subprocess.run(
            [sys.executable, TRANSLATE_SCRIPT_PATH, source_path, target_path,
             "--source", source_name, "--target", target_name],
            capture_output=True, text=True, timeout=1200,
        )
    except subprocess.TimeoutExpired:
        return [f"{target_name}: MISSING, translation from {source_name} timed out"]

    if result.returncode != 0:
        tail = "\n".join((result.stderr or result.stdout or "").strip().splitlines()[-20:])
        return [f"{target_name}: MISSING, translation from {source_name} failed:\n  {tail}"]

    return [f"{target_name}: TRANSLATED from {source_name} via translate_subs.py -> {os.path.basename(target_path)}"]


def write_summary_log(movie_dir, lines):
    with open(os.path.join(movie_dir, "summary.log"), "a") as f:
        f.write("\n".join(lines) + "\n")


def process_movie(movie_dir, position, total, api_key, openai_api_key):
    name = os.path.basename(movie_dir)
    prefix = f"[{position}/{total}] {name}:"

    video_path = find_video_file(movie_dir)
    if video_path is None:
        print(f"{prefix} no video file found, skipping")
        return
    video_stem = os.path.splitext(os.path.basename(video_path))[0]

    missing = [c for c, _ in LANGUAGES if not os.path.exists(os.path.join(movie_dir, f"{video_stem}.{c}.srt"))]

    log_lines = [f"=== Subtitles summary: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ==="]
    imdb_id = None
    movie_soup = None

    if missing:
        title, year = parse_title_and_year(video_path)
        tmdb_result = tmdb_search_movie(title, year, api_key)
        if not tmdb_result:
            log_lines.append(f"TMDb lookup: no match for title='{title}' year={year}")
        else:
            imdb_id = tmdb_get_imdb_id(tmdb_result["id"], api_key)
            if not imdb_id:
                log_lines.append(f"TMDb lookup: matched tmdb_id={tmdb_result['id']} but no imdb_id found")
            else:
                log_lines.append(f"TMDb lookup: title='{title}' year={year} -> imdb_id={imdb_id}")
                time.sleep(YTS_SUBS_REQUEST_DELAY_SECONDS)
                movie_soup, fetch_error = fetch_movie_page(imdb_id)
                if fetch_error:
                    log_lines.append(f"yts-subs movie page fetch failed: {fetch_error}")

    print(f"{prefix} checking subtitles...")
    for code, lang_name in LANGUAGES:
        result = ensure_subtitle(movie_dir, video_stem, code, lang_name, imdb_id, movie_soup)
        log_lines.extend(result)
        print(f"{prefix} {result[0]}")

    still_missing = [c for c, _ in LANGUAGES if not os.path.exists(os.path.join(movie_dir, f"{video_stem}.{c}.srt"))]
    if len(still_missing) == 1:
        missing_code = still_missing[0]
        present_code, present_name = next((c, n) for c, n in LANGUAGES if c != missing_code)
        missing_name = next(n for c, n in LANGUAGES if c == missing_code)
        print(f"{prefix} {missing_name} missing, translating from {present_name}...")
        result = translate_missing_subtitle(movie_dir, video_stem, present_code, present_name,
                                             missing_code, missing_name, openai_api_key)
        log_lines.extend(result)
        print(f"{prefix} {result[0]}")

    write_summary_log(movie_dir, log_lines)
    shutil.move(movie_dir, os.path.join(DONE_DIR, name))
    print(f"{prefix} finished, moved to done/")


def main():
    api_key = get_tmdb_api_key()
    if not api_key:
        print("Error: TMDB_API_KEY is not set (checked environment and backend/.env).")
        print("This tool cannot look up IMDb ids without it.")
        sys.exit(1)

    openai_api_key = get_env_value("OPENAI_API_KEY")
    if openai_api_key:
        os.environ["OPENAI_API_KEY"] = openai_api_key
    else:
        print("Note: OPENAI_API_KEY not set — missing subtitles won't be auto-translated as a fallback.")

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
        process_movie(os.path.join(IN_PROGRESS_DIR, name), position, total_in_progress, api_key, openai_api_key)

    total_pending = len(pending_names)
    for position, name in enumerate(pending_names, start=1):
        src = os.path.join(PENDING_DIR, name)
        dest = os.path.join(IN_PROGRESS_DIR, name)
        shutil.move(src, dest)
        process_movie(dest, position, total_pending, api_key, openai_api_key)

    print(f"Queue empty. {total_pending} movie(s) from pending/ processed this run.")


if __name__ == "__main__":
    main()
