{
	echo "Waiting for: $(ls ${hookdir}/initqueue/finished)"
	echo TEMPORARY FILES
	find /tmp
	ip -o addr show dev enx5254001234ee
	ip route | while read line; do echo "Route: $line"; done
	if curl 1.1.1.1 >/dev/null 2>&1; then 
		echo Internet connectivity detected!
	else
		echo Still waiting for internet...
	fi
	ip neigh | while read line; do echo "Neighbour: $line"; done
} >&2
