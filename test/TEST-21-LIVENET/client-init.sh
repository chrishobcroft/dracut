#!/bin/sh
: > /dev/watchdog
. /lib/dracut-lib.sh
. /lib/url-lib.sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
command -v plymouth > /dev/null 2>&1 && plymouth --quit
exec > /dev/console 2>&1

export TERM=linux
export PS1='initramfs-test:\w\$ '
stty sane
if getargbool 0 rd.shell; then
    [ -c /dev/watchdog ] && printf 'V' > /dev/watchdog
    strstr "$(setsid --help)" "control" && CTTY="-c"
    setsid $CTTY sh -i
fi

echo "made it to the rootfs! Powering down."
cat /proc/mounts

echo "rootfs-OK" | dd oflag=direct,dsync of=/dev/disk/by-id/ata-disk_marker 2>/dev/null

: > /dev/watchdog

sync
poweroff -f

























































