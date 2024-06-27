#!/bin/bash

check() {
    require_binaries bee || return 1
    return 255
}

depends() {
    echo livenet
}

install() {
    inst_binary -o bee
    inst_script "$moddir/bee-fetch-url.sh" "/bin/bee-fetch-url"
    inst_hook cmdline 28 "$moddir/register-bzz-handler.sh"
    inst_simple "$moddir/bee.service" /etc/systemd/system/bee.service
    inst_binary bee
    inst_binary ss
    inst_binary wget
    inst_simple "$moddir/bee.yaml" /etc/bee/bee.yaml
    inst_simple /var/lib/bee/password
    for key in libp2p_v2 pss swarm; do
	    inst_simple /var/lib/bee/keys/$key.key
    done

    #$SYSTEMCTL -q --root "$initdir" add-requires sysinit.target bee.service
}
