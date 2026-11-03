#!/usr/bin/env bash
# خط التطبيق (Tajawal)
set -e
mkdir -p assets/fonts
for w in Regular Medium Bold ExtraBold Black; do
  curl -fsSL -o assets/fonts/Tajawal-$w.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/tajawal/Tajawal-$w.ttf"
done
ls -la assets/fonts
