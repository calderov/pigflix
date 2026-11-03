#!/bin/bash
# Builds the Flutter Linux bundle, then packages it (plus mpv/ffmpeg, built
# from source — expect this to take a while) into a Flatpak and installs it
# for the current user. Pass the same --dart-define=BACKEND_URL=... you'd
# use for a plain Linux build, e.g.:
#   ./flatpak/build.sh --dart-define=BACKEND_URL=http://127.0.0.1:4000
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(cd "$repo_root/frontend" && flutter build linux --release "$@")

flatpak-builder \
  --user --install --force-clean \
  "$repo_root/flatpak/build-dir" \
  "$repo_root/flatpak/io.github.calderov.Pigflix.yaml"
