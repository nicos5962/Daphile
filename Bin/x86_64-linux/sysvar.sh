#! /bin/sh
scdir=/var/daphile/conf
sysconf=$scdir/config.sys
defaults=/usr/local/share/sysconf/defaults
name="$1"
exec {FD}<"$sysconf"
flock -x ${FD}
eval value=$(grep -hE \^"$name"= "$defaults" "$sysconf" 2>/dev/null | tail -n 1 | cut -f 2- -d =)
echo "$value"
