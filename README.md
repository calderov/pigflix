# Pigflix
A self-hosted streaming app for your ripped DVD/Blu-ray collection.
Drop your video files into a folder and make them browsable and playable from your local network.
<img width="1299" height="872" alt="image" src="https://github.com/user-attachments/assets/ab6b5042-1622-4a7b-ac94-22cbfc20aa78" />

## Architecture

Two independent projects in this repo:

- **`backend/`** — Node.js + Express. Owns the movie library: scanning,
  metadata, transcoding, and streaming.

- **`frontend/`** — Flutter app. Grid browser + video player. Built for web
  by default — in production it's served as static files *by the backend*,
  so the whole app is a single process on a single port. It can also be
  built as a native Linux desktop executable with the same look and
  behavior (see [Linux desktop client](#linux-desktop-client-optional)
  below).

```
pigflix/
├── backend/
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

Your movie files aren't part of this tree — they live wherever
`MOVIES_FOLDER` (set in `backend/.env`) points, anywhere on your
filesystem. Supported movie extensions: `.mp4 .mkv .avi .mov .m4v .wmv`.

## How it works

1. On boot, the backend walks `MOVIES_FOLDER` and compares it against the
   movies in the SQLite database.
2. For each new movie, the title and year are parsed from its filename and then searched against TMDb to fetch its metadata, cover art and background image.
3. Files removed from the movies folder are pruned from the DB, and its metadata metadata and transcoded files removed automatically.
4. If ENCODE_LIBRARY is set to true in the .env file the app will ensure a browser-playable files exists in `backend/transcoded/`, if not it will transcode the movies to H.264/ACC and save them on `backend/transcoded`.

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
```
Edit .env and set:
- `MOVIES_FOLDER=<path to your movie files>` to let Pigflix know where are your movies are stored (movies in subfolders are fine).
- `TMDB_API_KEY=<your key>` to fetch movie posters, backdrops and metadata.
- `ADMIN_PASSWORD=<a password>` to enable admin mode in the frontend or leave blank to disable admin mode entirely.

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

The backend scans the movies folder, fetches metadata for anything new, and serves both the API and the built frontend on port 4000. Open
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
rm -rf "$MOVIES_FOLDER"/*
```

Restart the backend (`npm start`) afterwards; it will treat any files still
in `MOVIES_FOLDER` as new and re-register them from scratch.

### Moving your movies folder later

Want to relocate your movie files to a different drive/path? Movies are
tracked in the database by their path *relative to* `MOVIES_FOLDER`, so no
database changes are needed — just:

1. Stop the backend.
2. Move the *contents* of the old `MOVIES_FOLDER` to the new location,
   keeping the same subfolder structure.
3. Update `MOVIES_FOLDER` in `.env` to the new location.
4. Restart the backend — your existing library, metadata, and transcoded
   cache all keep working unchanged.

### Linux desktop client (optional)

Instead of (or alongside) the web build, you can build `frontend/` as a
native Linux executable that talks to the same backend — same grid, player,
and subtitles, running as a regular desktop window instead of in a browser.

**Extra prerequisites** (on top of the ones above):

```bash
flutter config --enable-linux-desktop
sudo apt install libmpv-dev libgtk-3-dev libx11-dev libxi-dev
```
`libmpv-dev` is needed at build time for video playback (via
[`media_kit`](https://pub.dev/packages/media_kit), since the official
`video_player` plugin has no Linux backend of its own). The GTK/X11 `-dev`
packages are needed to build the native window shell; most Linux desktops
already have them.

**Build:**

```bash
cd frontend
flutter pub get
flutter build linux --release --dart-define=BACKEND_URL=http://<LAN-IP>:4000
```

**Run:**

```bash
./build/linux/x64/release/bundle/frontend
```

The bundle (`build/linux/x64/release/bundle/`) is self-contained — copy the
whole folder if you want to run it from somewhere else, but keep `frontend`,
`data/`, and `lib/` together. The *machine running it* needs the `libmpv2`
runtime package installed (`sudo apt install libmpv2`) even if it wasn't the
one that built it.

Fullscreen (`F11`, from any screen) toggles a real OS window fullscreen and
persists as you navigate between screens, matching the web version's
browser-fullscreen behavior.

#### Flatpak package (optional)

The plain Linux build above works fine, but on Wayland desktops (GNOME,
Pantheon/elementary OS, etc.) its window won't show the Pigflix icon in
alt-tab or the dock — those resolve a window's icon through an *installed*
`.desktop` file, which a bare local build doesn't have. Packaging it as a
Flatpak fixes this properly: `flatpak install` exports the `.desktop` file
and icon for you, and `flatpak uninstall` removes them cleanly.

**Extra prerequisites:**

```bash
sudo apt install flatpak-builder
flatpak install flathub org.gnome.Platform//50 org.gnome.Sdk//50
flatpak install flathub org.gtk.Gtk3theme.adw-gtk3-dark
```
The last one is a GTK3 theme with a real dark variant — plain GTK3 apps
don't follow the system dark-mode preference inside a Flatpak sandbox the
way GTK4/libadwaita apps do, and the runtime's stock Adwaita theme has no
dark variant of its own, so without it the window decoration stays light
regardless of your system theme.

**Build and install** (builds the Linux bundle above, then packages it —
this also compiles `mpv`/`ffmpeg` from source, since Flatpak sandboxes can't
see the host's `libmpv`, so expect it to take a while, roughly 20–50
minutes depending on your machine):

```bash
./flatpak/build.sh --dart-define=BACKEND_URL=http://<LAN-IP>:4000
```

**Run:**

```bash
flatpak run io.github.calderov.Pigflix
```

**Remove:**

```bash
flatpak uninstall io.github.calderov.Pigflix
```

**Share it:** pass `--bundle` to also export a standalone `flatpak/pigflix.flatpak`
file, installable on another machine with `flatpak install pigflix.flatpak`
(no Flathub lookup needed, though the recipient still needs the
`org.gnome.Platform//50` runtime, pulled automatically from Flathub on
install if missing). `BACKEND_URL` is baked in at build time, so the bundle
only works for whoever you built it for — pointed at your backend's LAN IP,
it'll only work for people on that same LAN:

```bash
./flatpak/build.sh --bundle --dart-define=BACKEND_URL=http://<LAN-IP>:4000
```

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

- The frontend isn't set up to run as a native mobile app — only web and
  Linux desktop (see [Linux desktop
  client](#linux-desktop-client-optional)) are supported native targets.

- If the server's LAN IP changes (e.g. DHCP reassignment), the frontend must
  be rebuilt with the new `BACKEND_URL`.
