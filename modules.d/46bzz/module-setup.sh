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
    inst_simple "$moddir/bee.yaml" /etc/bee/bee.yaml

    #$SYSTEMCTL -q --root "$initdir" add-requires sysinit.target bee.service
}
