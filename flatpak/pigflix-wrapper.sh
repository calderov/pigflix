#!/bin/sh
# The Flutter-built bundle (frontend/lib/data relative to each other) lives
# under /app/pigflix/ as a single unit — see flatpak/io.github.calderov.Pigflix.yaml.
exec /app/pigflix/frontend "$@"
