#!/bin/bash
# Builds the Flutter Linux bundle, then packages it (plus mpv/ffmpeg, built
# from source — expect this to take a while) into a Flatpak and installs it
# for the current user. Pass the same --dart-define=BACKEND_URL=... you'd
# use for a plain Linux build, e.g.:
#   ./flatpak/build.sh --dart-define=BACKEND_URL=http://127.0.0.1:4000
#
# Pass --bundle to also export a standalone flatpak/pigflix.flatpak file,
# shareable with anyone who has Flatpak (`flatpak install pigflix.flatpak`).
# Note: BACKEND_URL is baked in at build time, so a shared bundle only works
# for people pointed at the same backend address you built it with.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_id="io.github.calderov.Pigflix"

bundle=false
flutter_args=()
for arg in "$@"; do
  if [ "$arg" = "--bundle" ]; then
    bundle=true
  else
    flutter_args+=("$arg")
  fi
done

(cd "$repo_root/frontend" && flutter build linux --release "${flutter_args[@]}")

flatpak-builder \
  --user --install --force-clean \
  --repo="$repo_root/flatpak/repo" \
  "$repo_root/flatpak/build-dir" \
  "$repo_root/flatpak/io.github.calderov.Pigflix.yaml"

if [ "$bundle" = true ]; then
  flatpak build-bundle \
    "$repo_root/flatpak/repo" \
    "$repo_root/flatpak/pigflix.flatpak" \
    "$app_id" master
  echo "Bundle written to flatpak/pigflix.flatpak"
fi
