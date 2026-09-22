# Pigflix
A self-hosted streaming app for your ripped DVD/Blu-ray collection.
Drop your video files into a folder and make them browsable and playable from your local network.

## Architecture

Two independent projects in this repo:

- **`backend/`** — Node.js + Express. Owns the movie library: scanning,
  metadata, transcoding, and streaming.

- **`frontend/`** — Flutter app, built for web. Grid browser + video player.
  In production it's served as static files *by the backend*, so the whole
  app is a single process on a single port.

```
pigflix/
├── backend/
│   ├── movies/       # put your ripped video files here (flat or in subfolders)
│   ├── metadata/     # per-movie info.json + poster.jpg + backdrop.jpg (generated)
│   ├── transcoded/   # cached playback-ready .mp4 per movie (generated but optional)
│   ├── data/         # SQLite database tracking your movies
│   ├── src/
│   └── index.js
└── frontend/
    ├── lib/
    │   ├── models/movie.dart
    │   ├── services/api_service.dart
    │   ├── screens/
    │   └── widgets/
    └── build/web/
```

## How it works

1. On boot, the backend walks `backend/movies/` and compares it against the
   movies in the SQLite database.
2. For each new movie, the title and year are parsed from its filename and then searched against TMDb to fetch its metadata, cover art and background image.
3. Files removed from `backend/movies/` are pruned from the DB, and its metadata metadata and transcoded files removed automatically.
4. If ENCODE_LIBRARY is set to true in the .env file the app will ensure a browser-playable files exists in `backend/transcoded/`, if not it will transcode the movies in `backend/movies/` to H.264/ACC and save them on `backend/transcoded`.

## Setup on a new machine

### Prerequisites

- **Node.js** (v20+; developed against v24)
- **ffmpeg** and **ffprobe** on `PATH` (`ffmpeg -version` should work)
- **Flutter SDK** (stable channel; developed against 3.44), with web support
  enabled (`flutter config --enable-web` if it isn't already)
- A free **TMDb API key**: https://www.themoviedb.org/settings/api

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env
# edit .env and set TMDB_API_KEY=<your key>
# also set ADMIN_PASSWORD=<a password> to enable admin mode in the frontend
# (see "Admin mode" below) — leave it blank to disable admin mode entirely
```

Put your ripped video files into `backend/movies/` (subfolders are fine).
Supported extensions: `.mp4 .mkv .avi .mov .m4v .wmv`.

### 2. Frontend

Find this machine's LAN IP (so other devices on your network can reach it):

```bash
hostname -I   # Linux
# or: ipconfig getifaddr en0   (macOS, Wi-Fi)
```

Build the web app, pointing it at that IP and the backend's port:

```bash
cd frontend
flutter pub get
flutter build web --release --dart-define=BACKEND_URL=http://<LAN-IP>:4000
```

### 3. Run it

```bash
cd backend
npm start
```

The backend scans `movies/`, fetches metadata for anything new, and serves
both the API and the built frontend on port 4000. Open
`http://<LAN-IP>:4000` from any browser on your network (or
`http://localhost:4000` on the server itself).

First playback of each movie triggers its one-time remux/transcode — expect
a short wait (seconds for already-compatible files, longer for older/exotic
codecs) before video starts.

### Checking whether it's running

```bash
pgrep -fa "node index.js"                        # process
lsof -i :4000                                     # port
curl http://localhost:4000/api/health             # should return {"status":"ok"}
```

### Resetting to a fresh install
To wipe the generated state (database, metadata, transcoded cache) and start
over, **keeping** your source video files:

```bash
cd backend
rm -f data/pigflix.db data/pigflix.db-wal data/pigflix.db-shm
rm -rf metadata/* transcoded/*
```

To also remove the source video files themselves (irreversible — only do
this if you actually want to delete your ripped movies), additionally:

```bash
rm -rf movies/*
```

Restart the backend (`npm start`) afterwards; it will treat any files still
in `movies/` as new and re-register them from scratch.

### Admin mode
The lock button next to "refresh library" on the grid screen prompts for
`ADMIN_PASSWORD` (set in `backend/.env`) and, once unlocked, reveals the "Fix
match" button on the movie detail screen, which lets you re-run the TMDb
search with a given title/year (or an exact `id:<tmdb id>`) for a movie
that was never matched or was matched to the wrong film. 

Click the lock again
to leave admin mode. This is a UI convenience, not real access control — see
the limitations below.

### Notes / known limitations

- No authentication — anyone on your LAN who can reach the port can browse
  and stream. Fine for a home network; don't expose this to the internet
  as-is. Admin mode's password check only gates the frontend's "Fix match"
  button; the underlying `/api/movies/:id/retry-metadata` and
  `/api/admin/login` endpoints are not otherwise protected.

- The Flutter fullscreen behavior uses `dart:html`, which only works on the
  web target (the frontend isn't set up to run as a native mobile/desktop
  app).

- If the server's LAN IP changes (e.g. DHCP reassignment), the frontend must
  be rebuilt with the new `BACKEND_URL`.
