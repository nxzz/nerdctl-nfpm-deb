#!/bin/sh
set -e

if [ -d /run/systemd/system ]; then
	systemctl daemon-reload || true
	# deb の慣例どおり、初回インストール時に containerd / buildkit を有効化・起動する
	if [ "$1" = "configure" ] && [ -z "$2" ]; then
		systemctl enable --now containerd.service || true
		systemctl enable --now buildkit.service || true
	else
		# アップグレード時は動いているものだけ再起動
		systemctl try-restart containerd.service buildkit.service || true
	fi
fi

exit 0
