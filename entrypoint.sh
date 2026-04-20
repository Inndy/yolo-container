#!/bin/bash
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}
DEV_UID=$(id -u dev)
DEV_GID=$(id -g dev)
NEED_CHOWN=0

exec 3>/.ready
flock -x 3

if [ "$HOST_GID" != "$DEV_GID" ]; then
	conflict_group=$(getent group "$HOST_GID" | cut -d: -f1)
	if [ -n "$conflict_group" ] && [ "$conflict_group" != "dev" ] && [ "$HOST_GID" != "0" ]; then
		groupdel "$conflict_group" 2>/dev/null
	fi
	groupmod -g "$HOST_GID" dev 2>/dev/null
	NEED_CHOWN=1
fi

if [ "$HOST_UID" != "$DEV_UID" ]; then
	conflict_user=$(getent passwd "$HOST_UID" | cut -d: -f1)
	if [ -n "$conflict_user" ] && [ "$conflict_user" != "dev" ]; then
		userdel "$conflict_user" 2>/dev/null
	fi
	usermod -u "$HOST_UID" dev 2>/dev/null
	NEED_CHOWN=1
fi

if [ "$NEED_CHOWN" = 1 ]; then
	chown -R "$HOST_UID:$HOST_GID" /home/dev
fi

exec 3>&-
exec "$@"
