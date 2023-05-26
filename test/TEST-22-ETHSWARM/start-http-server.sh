ls ${hookdir}/initqueue/finished | while read line; do
    echo "Waiting for $line..."
done

if ! pgrep lighttpd; then
	lighttpd -D -f /etc/lighttpd/lighttpd.conf &
fi
