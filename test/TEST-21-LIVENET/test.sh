#!/bin/bash

[ -z "$USE_NETWORK" ] && USE_NETWORK="network-legacy"

# shellcheck disable=SC2034
TEST_DESCRIPTION="live root filesystem served over HTTP with $USE_NETWORK"

KVERSION=${KVERSION-$(uname -r)}

# Uncomment this to debug failures
#DEBUGFAIL="rd.debug loglevel=7 rd.break=initqueue rd.shell"
SERVER_DEBUG="rd.debug loglevel=7"
#SERIAL="unix:/tmp/server.sock"

run_server() {
    # Start server first
    echo "LIVENET TEST SETUP: Starting DHCP/HTTP server"
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive_args disk_index disk_args "$TESTDIR"/server.img root 1

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net socket,listen=127.0.0.1:12320 \
        -net nic,macaddr=52:54:00:12:34:56,model=e1000 \
        -serial "${SERIAL:-"file:$TESTDIR/server.log"}" \
        -device i6300esb -watchdog-action poweroff \
        -append "panic=1 oops=panic softlockup_panic=1 root=LABEL=dracut rootfstype=ext3 rw console=ttyS0,115200n81 selinux=0 $SERVER_DEBUG" \
        -initrd "$TESTDIR"/initramfs.server \
        -pidfile "$TESTDIR"/server.pid -daemonize || return 1
    chmod 644 "$TESTDIR"/server.pid || return 1

    # Cleanup the terminal if we have one
    tty -s && stty sane

    if ! [[ $SERIAL ]]; then
        while ! grep -q  'server started (lighttpd' $TESTDIR/server.log; do
            sleep 0.6
        done
    else
        echo Sleeping 10 seconds to give the server a head start
        sleep 10
    fi
}

test_client() {
    local cmdline="root=live:http://192.168.50.1/squashfs.img ip=192.168.50.101 netmask=255.255.255.0"
    local nfsinfo opts found expected
    local mac=52:54:00:12:34:00

    echo "client test start: $cmdline"

    # need this so kvm-qemu will boot (needs non-/dev/zero local disk)
    dd if=/dev/zero of="$TESTDIR"/marker.img bs=1MiB count=1 2>/dev/null
    declare -a disk_args=()
    # shellcheck disable=sc2034
    declare -i disk_index=0
    qemu_add_drive_args disk_index disk_args "$TESTDIR"/marker.img marker
    cmdline="$cmdline rd.net.timeout.dhcp=30"

    if ! "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -net nic,macaddr="$mac",model=e1000 \
        -net socket,connect=127.0.0.1:12320 \
        -device i6300esb -watchdog-action poweroff \
        -append "panic=1 oops=panic softlockup_panic=1 systemd.crash_reboot rd.shell=0 $cmdline $debugfail rd.retry=10 quiet ro console=ttyS0,115200n81 selinux=0" \
        -initrd "$TESTDIR"/initramfs.testing; then
        echo "Oh no! I hate this!"
        return 1
    fi

    # shellcheck disable=sc2181
    if ! grep --binary-files=binary -F -m 1 -q rootfs-OK "$TESTDIR"/marker.img; then
        echo "CLIENT TEST END: $test_name [FAILED - BAD EXIT]"
        return 1
    fi

    echo "CLIENT TEST END: [OK]"
    return 0
}


test_run() {
    if [[ -s server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi

    if ! run_server; then
        echo "Failed to start server" 1>&2
        return 1
    fi

    echo "Server is now running."
    test_client

    ret=$?

    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi

    return $ret
}

make_server_root() {
    # Prepare server rootfs
    rm -rf -- "$TESTDIR"/overlay
    (
        mkdir -p "$TESTDIR"/server/overlay/source
        # shellcheck disable=SC2030
        export initdir=$TESTDIR/server/overlay/source
        # shellcheck disable=SC1090
        . "$basedir"/dracut-init.sh

        (
            cd "$initdir" || exit
            mkdir -p dev sys proc run etc var/run tmp var/lib/dhcpd srv
        )

        inst_multiple sh ls shutdown poweroff stty cat ps ln ip \
            dmesg mkdir cp ping exportfs \
            modprobe showmount tcpdump \
            sleep mount chmod rm lighttpd curl
        for _terminfodir in /lib/terminfo /etc/terminfo /usr/share/terminfo; do
            if [ -f "${_terminfodir}"/l/linux ]; then
                inst_multiple -o "${_terminfodir}"/l/linux
                break
            fi
        done

        [ -f /etc/netconfig ] && inst_multiple /etc/netconfig
        type -P dhcpd > /dev/null && inst_multiple dhcpd
        [ -x /usr/sbin/dhcpd3 ] && inst /usr/sbin/dhcpd3 /usr/sbin/dhcpd
        instmods ipv6 lockd af_packet

        # init
        inst ./server-init.sh /sbin/init

        # client fs image
        inst $TESTDIR/squashfs.img /srv/squashfs.img

        # files
        inst_simple /etc/os-release
        inst ./hosts /etc/hosts
        
        inst ./lighttpd.conf /etc/lighttpd/lighttpd.conf
        inst ./dhcpd.conf /etc/dhcpd.conf
        inst_multiple -o {,/usr}/etc/nsswitch.conf {,/usr}/etc/rpc \
            {,/usr}/etc/protocols {,/usr}/etc/services
        inst_multiple -o rpc.idmapd /etc/idmapd.conf

        _nsslibs=$(
            cat "$dracutsysrootdir"/{,usr/}etc/nsswitch.conf 2> /dev/null \
                | sed -e '/^#/d' -e 's/^.*://' -e 's/\[NOTFOUND=return\]//' \
                | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' '|'
        )
        _nsslibs=${_nsslibs#|}
        _nsslibs=${_nsslibs%|}
        inst_libdir_file -n "$_nsslibs" 'libnss_*.so*'

        inst /etc/passwd /etc/passwd
        inst /etc/group /etc/group

        #cp -a /etc/ld.so.conf* "$initdir"/etc
        #ldconfig -r "$initdir"
        dracut_kernel_post
    )

    # Prepare overlay for rootfs-builder initramfs
    (
        # shellcheck disable=SC2030
        # shellcheck disable=SC2031
        export initdir=$TESTDIR/server/overlay
        # shellcheck disable=SC1090
        . "$basedir"/dracut-init.sh
        inst_multiple sfdisk mkfs.ext3 poweroff cp umount sync dd
        inst_hook initqueue 01 ./create-root.sh
        inst_hook initqueue/finished 01 ./finished-false.sh
    )

    # Make initramfs
    "$basedir"/dracut.sh -q -l -i "$TESTDIR"/server/overlay / \
        -m "bash rootfs-block kernel-modules qemu" \
        -d "piix ide-gd_mod ata_piix ext3 sd_mod" \
        --nomdadmconf \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.makeroot "$KVERSION" || return 1
    rm -rf -- "$TESTDIR"/server

    # Create disks for rootfs-builder
    dd if=/dev/zero of="$TESTDIR"/server.img bs=1MiB count=80 2>/dev/null
    dd if=/dev/zero of="$TESTDIR"/marker.img bs=1MiB count=1 2>/dev/null
    declare -a disk_args=()
    # shellcheck disable=SC2034
    declare -i disk_index=0
    qemu_add_drive_args disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive_args disk_index disk_args "$TESTDIR"/server.img root

    # Execute rootfs-builder
    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "root=/dev/dracut/root rw rootfstype=ext3 quiet console=ttyS0,115200n81 selinux=0" \
        -initrd "$TESTDIR"/initramfs.makeroot || return 1

    grep -U --binary-files=binary -F -m 1 -q dracut-root-block-created "$TESTDIR"/marker.img || return 1

}

make_client_root() {
    # Prepare rootfs
    rm -rf -- "$TESTDIR"/overlay
    (
        # shellcheck disable=SC2030
        # shellcheck disable=SC2031
        export initdir=$TESTDIR/client/overlay/source/
        # shellcheck disable=SC1090
        . "$basedir"/dracut-init.sh

        (
            cd "$initdir" || exit
            mkdir -p dev sys proc etc run root usr var/lib/nfs/rpc_pipefs
            echo "TEST FETCH FILE" > root/fetchfile
        )

        inst_multiple sh shutdown poweroff stty cat ps ln ip dd \
            mount dmesg mkdir cp ping grep setsid ls vi less cat sync \
            findmnt find curl
        for _terminfodir in /lib/terminfo /etc/terminfo /usr/share/terminfo; do
            if [ -f "${_terminfodir}"/l/linux ]; then
                inst_multiple -o "${_terminfodir}"/l/linux
                break
            fi
        done

        inst_simple "${basedir}/modules.d/99base/dracut-lib.sh" "/lib/dracut-lib.sh"
        inst_simple "${basedir}/modules.d/99base/dracut-dev-lib.sh" "/lib/dracut-dev-lib.sh"
        inst_simple "${basedir}/modules.d/45url-lib/url-lib.sh" "/lib/url-lib.sh"
        inst_simple "${basedir}/modules.d/40network/net-lib.sh" "/lib/net-lib.sh"
        inst_simple "${basedir}/modules.d/95nfs/nfs-lib.sh" "/lib/nfs-lib.sh"
        inst_binary "${basedir}/dracut-util" "/usr/bin/dracut-util"
        ln -s dracut-util "${initdir}/usr/bin/dracut-getarg"
        ln -s dracut-util "${initdir}/usr/bin/dracut-getargs"

        inst ./client-init.sh /sbin/init
        inst_simple /etc/os-release
        inst_multiple -o {,/usr}/etc/nsswitch.conf
        inst /etc/passwd /etc/passwd
        inst /etc/group /etc/group

        _nsslibs=$(
            cat "$dracutsysrootdir"/{,usr/}etc/nsswitch.conf 2> /dev/null \
                | sed -e '/^#/d' -e 's/^.*://' -e 's/\[NOTFOUND=return\]//' \
                | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' '|'
        )
        _nsslibs=${_nsslibs#|}
        _nsslibs=${_nsslibs%|}
        inst_libdir_file -n "$_nsslibs" 'libnss_*.so*'

        cp -a /etc/ld.so.conf* "$initdir"/etc
        ldconfig -r "$initdir"
    )

    mksquashfs $TESTDIR/client/overlay/source $TESTDIR/squashfs.img -quiet
}

test_setup() {
    export kernel=$KVERSION
    export srcmods="/lib/modules/$kernel/"
    # Detect lib paths

    make_client_root || return 1 # yield $TESTDIR/squashfs.img
    [ -f $TESTDIR/squashfs.img ] || return 1
    make_server_root || return 1
    
    # Prepare overlay for client initramfs
    (
        # shellcheck disable=SC2031
        # shellcheck disable=SC2030
        export initdir="$TESTDIR"/overlay
        mkdir -p "$TESTDIR"/overlay
        # shellcheck disable=SC1090
        . "$basedir"/dracut-init.sh
        inst_multiple poweroff shutdown
        inst_hook shutdown-emergency 000 ./hard-off.sh
        inst_hook emergency 000 ./hard-off.sh
        inst_simple ./client.link /etc/systemd/network/01-client.link
    )

    # Make client initramfs
    "$basedir"/dracut.sh -l -q -i "$TESTDIR"/overlay / \
        -o "plymouth" \
        -a "livenet debug watchdog ${USE_NETWORK}" \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.testing "$KVERSION" || return 1

    # Overlay for server initramfs
    (
        # shellcheck disable=SC2031
        export initdir="$TESTDIR"/overlay
        # shellcheck disable=SC1090
        . "$basedir"/dracut-init.sh
        rm "$initdir"/etc/systemd/network/01-client.link
        inst_simple ./server.link /etc/systemd/network/01-server.link
        inst_hook pre-mount 99 ./wait-if-server.sh
    )

    # Make server initramfs
    "$basedir"/dracut.sh -l -i -q "$TESTDIR"/overlay / \
        -m "dash rootfs-block debug kernel-modules watchdog qemu network network-legacy" \
        -d "af_packet piix ide-gd_mod ata_piix ext3 sd_mod e1000 i6300esb" \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.server "$KVERSION" || return 1

    rm -rf -- "$TESTDIR"/overlay
}

test_cleanup() {
    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions
