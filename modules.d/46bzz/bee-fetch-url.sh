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
echo Waiting for peers...  >&2
sleep 10
# hacky wait for enough peers.
# Would be better to wait on curl -s localhost:1633/peers | jq -r 'length(.peers)' > 25
# or similar. But we didn't install jq.

outdir="$(mkuniqdir /tmp bzz_fetch_url)"
(
    cd "$outdir" || exit
    wget $http_url >&2
#    while ! curl --retry 30 --retry-connrefused --no-fail -LO $http_url >&2; do
#        echo Failed to fetch, trying again in 5s... >&2
#        sleep 5
#	: > /dev/watchdog
#    done
)
outloc="$outdir/$(ls -A "$outdir")"
if [ -n $outloc ]; then
    if [ -s $outloc ]; then
        echo "Downloaded image to $outloc." >&2
    else
        echo "Uh oh! Downloaded a 0 byte file!" >&2
    fi
else
    echo "Nothing downloaded!" >&2
fi

# DON'T CHANGE THIS!
echo $outloc
