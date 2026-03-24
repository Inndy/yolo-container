#!/bin/bash
MY_UID=$(id -u)
MY_GID=$(id -g)
if ! getent group "$MY_GID" >/dev/null 2>&1; then
	echo "dev:x:${MY_GID}:" >> /etc/group
fi
if ! getent passwd "$MY_UID" >/dev/null 2>&1; then
	echo "dev:x:${MY_UID}:${MY_GID}:dev:/home/dev:/bin/bash" >> /etc/passwd
fi
exec "$@"
