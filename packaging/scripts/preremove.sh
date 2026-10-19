#!/bin/sh
set -e

if [ -d /run/systemd/system ] && [ "$1" = "remove" ]; then
	systemctl disable --now buildkit.service stargz-snapshotter.service containerd.service || true
fi

exit 0
