#!/bin/sh
. /lib/url-lib.sh
. /lib/net-lib.sh
#set -e

url="$1" outloc="$2"
#prefix="https://download.gateway.ethswarm.org/bzz/"
prefix="http://localhost:1633/bzz/"
http_url="${prefix}${url#bzz://}"

if ! systemctl status bee.service >/dev/null; then
    systemctl start bee.service
fi
while ! curl -s http://localhost:1633/health >/dev/null; do
    sleep 5
done
echo "bee API detected!" >&2
sleep 5 
# hacky wait for enough peers. 
# Would be better to wait on curl -s localhost:1633/peers | jq -r 'length(.peers)' > 25
# or similar.

outdir="$(mkuniqdir /tmp bzz_fetch_url)"
(
    cd "$outdir" || exit
    while ! curl --fail -LOs $http_url; do
        echo Failed to fetch, trying again in 5s... >&2
        sleep 5
    done
)
outloc="$outdir/$(ls -A "$outdir")"
echo $outloc
