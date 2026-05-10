#!/usr/bin/env bash
set -euo pipefail

IMAGE="/home/simonnieder/wallpapers/grainy_gradient.jpg"

exec matugen image "$IMAGE" --source-color-index 0
