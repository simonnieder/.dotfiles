#!/bin/bash

killall -q waybar
while pgrep -x waybar >/dev/null; do
  sleep 0.1
done

waybar >/tmp/waybar.log 2>&1 &
