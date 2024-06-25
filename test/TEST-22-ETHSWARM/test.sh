#!/bin/bash

[ -z "$USE_NETWORK" ] && USE_NETWORK="network-legacy"

# shellcheck disable=SC2034
TEST_DESCRIPTION="live root filesystem served from EthSwarm with bee client and $USE_NETWORK"

KVERSION=${KVERSION-$(uname -r)}

# Uncomment this to debug failures
#DEBUGFAIL="rd.debug loglevel=7 rd.break=initqueue rd.shell"
SERVER_DEBUG="rd.debug loglevel=7"
#SERIAL="unix:/tmp/server.sock"

mac=52:54:00:12:34:ee

run_with_cmdline() {
    local cmdline="$1"
    local nfsinfo opts found expected

    echo "Booting $cmdline"

    # need this so kvm-qemu will boot (needs non-/dev/zero local disk)
    dd if=/dev/zero of="$TESTDIR"/marker.img bs=1MiB count=1 2>/dev/null
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive_args disk_index disk_args "$TESTDIR"/marker.img marker
    cmdline="$cmdline rd.net.timeout.dhcp=30"

    if ! "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -device i6300esb -watchdog-action poweroff \
	-nic user,model=e1000,mac=$mac,restrict=off \
        -append "panic=1 oops=panic softlockup_panic=1 systemd.crash_reboot rd.shell=0 $cmdline $debugfail rd.retry=10 ro quiet console=ttyS0,115200n81 selinux=0" \
        -initrd "$TESTDIR"/initramfs.testing; then
        echo "Oh no! I hate this!"
        return 1
    fi

    # shellcheck disable=sc2181
    if ! grep --binary-files=binary -F -m 1 -q rootfs-OK "$TESTDIR"/marker.img; then
        return 1
    fi

}

run_ip_dhcp() {
    local netargs="ip=dhcp"
    local swarmhash="e305446d58fb09914e3dd85977afc39df27caa41b58391cacb1b4b37497a48a9"
    #local prefix="https://download.gateway.ethswarm.org/bzz/"
    local prefix="bzz://"

    run_with_cmdline "root=live:${prefix}${swarmhash} $netargs rd.neednet"
}

run_ip_static() {
    local ip=10.0.2.100
    local gw=10.0.2.2
    local netargs="ip=$ip::$gw:255.255.255.0:grubbler:enx5254001234ee:none:10.0.2.3"
    local swarmhash="e305446d58fb09914e3dd85977afc39df27caa41b58391cacb1b4b37497a48a9"
    #local prefix="https://download.gateway.ethswarm.org/bzz/"
    local prefix="bzz://"

    run_with_cmdline "root=live:${prefix}${swarmhash} $netargs rd.neednet"
}

test_run() {
    run_ip_dhcp
    echo "Test completed with exit code $?."
    echo "CLIENT TEST END: [OK]"
    return 0
}

bee_version=1.16.1
bee_pkg=bee-$bee_version.x86_64.rpm
bee_repo=https://github.com/ethersphere/bee/releases/download
bee_pkg_url=$bee_repo/v$bee_version/$bee_pkg

test_setup() {
    # Target: initramfs.testing

    export kernel=$KVERSION
    export srcmods="/lib/modules/$kernel/"
    
    if ! command -v bee >/dev/null; then
        wget $bee_pkg_url
	rpm -i $bee_pkg
    fi

    # Prepare overlay for initramfs
    (
        export initdir="$TESTDIR"/overlay
        mkdir -p "$TESTDIR"/overlay
        mkdir "$TESTDIR"/srv
        # shellcheck disable=SC1090
        . "$basedir"/dracut-init.sh
        inst_multiple poweroff shutdown 
        inst_hook shutdown-emergency 000 ./hard-off.sh
        inst_hook emergency 000 ./hard-off.sh
        inst_hook initqueue 00 ./debug.sh
	#inst_hook pre-mount 50 ./print-env.sh
        inst_simple ./client.link /etc/systemd/network/01-client.link
	# bee state stuff
	#inst_simple /var/lib/bee/password /var/lib/bee/password
	#inst_dir /var/lib/bee/keys /var/lib/bee/keys
	#for k in libp2p_v2 pss swarm; do
	#    inst_simple /var/lib/bee/keys/$k.key /var/lib/bee/keys/$k.key
        #done
    )

    # Make initramfs
    "$basedir"/dracut.sh -l -q -i "$TESTDIR"/overlay / \
        -o "plymouth" \
        -a "bzz debug watchdog ${USE_NETWORK}" \
        --no-hostonly-cmdline -N \
        -f "$TESTDIR"/initramfs.testing "$KVERSION" || return 1

    rm -rf -- "$TESTDIR"/overlay
}

test_cleanup() {
    [ -f $bee_pkg ] && rm $bee_pkg
    if [[ -s $TESTDIR/server.pid ]]; then
        kill -TERM "$(cat "$TESTDIR"/server.pid)"
        rm -f -- "$TESTDIR"/server.pid
    fi
}

# shellcheck disable=SC1090
. "$testdir"/test-functions
