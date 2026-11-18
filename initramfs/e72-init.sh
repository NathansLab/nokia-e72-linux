#!/bin/busybox sh
# Nokia E72 /init: the stock init.sh does the work, /bin/e72-boot (hooked into
# it by build-e72.sh) adds the E72 parts
exec /bin/busybox sh /init.e5
