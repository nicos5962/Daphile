#! /bin/bash
#
# System status for the Daphile Info page.
# Adapted from the Daphile OS "Info" CGI: prints "label<TAB>value" lines, one
# per item; the Info.pm settings page escapes and renders them.
#
# DAPHILE_INFO_PATHS : colon separated directories to report free space for
#
here=$(dirname "$(readlink -f "$0")")

row() {
	printf '%s\t%s\n' "$1" "$2"
}

size_format() {
	local size=$1
	local unit="B"
	if [[ $size -ge 1000000000000 ]]
	then
		size=$(($size / 100000000000))
		unit="TB"
	elif [[ $size -ge 1000000000 ]]
	then
		size=$(($size / 100000000))
		unit="GB"
	elif [[ $size -ge 1000000 ]]
	then
		size=$(($size / 100000))
		unit="MB"
	elif [[ $size -ge 1000 ]]
	then
		size=$(($size / 100))
		unit="kB"
	else
		size=$(($size * 10))
	fi
	if [[ $size -lt 1000 && "$unit" != "B" ]]
	then
		size=$(echo $size | awk '{printf("%.1f",$1/10)}')
	else
		size=$(($size / 10))
	fi
	echo "${size}$unit"
}

freq_format() {
	local z=$(( ( $1 + 500 ) / 1000 ))
	if [[ $z -lt 1000 ]]
	then
		z="$z MHz"
	else
		z="$(echo $z|sed -e 's/\([0-9]\{3\}\)$/\.\1/') GHz"
	fi
	echo "$z"
}

diskfree() {
	local dir= size= free= percent= out=
	local -a dirs
	IFS=: read -ra dirs <<< "${DAPHILE_INFO_PATHS}"
	for dir in "${dirs[@]}"
	do
		[[ -d "$dir" ]] || continue
		read size free < <(/usr/bin/timeout -s 9 5 df -B 1 --output=size,avail "$dir" 2> /dev/null | tail -n 1)
		[[ "$free" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ && $size -gt 0 ]] || continue
		percent=$(echo $size $free | awk '{printf("%d%%",(100*$2/$1+0.5))}')
		out="$(size_format $free) ($percent) free of $(size_format $size) - $dir"
		[[ $free -eq 0 ]] && out+=" - FULL"
		row "Free storage" "$out"
	done
}

cpuinfo() {
	local p=$(ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2> /dev/null)
	local cpus=$(echo "$p" | grep -c .)
	local info= ind=0 f= c=

	[[ $cpus -eq 0 ]] && return
	if [[ $cpus -eq 1 ]]
	then
		info="$(freq_format $(cat $p))"
	else
		for c in $p
		do
			f=$(cat $c)
			info+="CPU${ind}: $(freq_format $f), "
			let $(( ind++ ))
		done
		info=${info%, }
	fi
	row "CPU frequency" "$info"
}

loadavg() {
	row "System load (1, 5, 15 min)" "$(cut -f 1-3 -d ' ' /proc/loadavg)"
}

freemem() {
	local total=$(free -m | grep -E "^Mem:" | awk '{print $2}')
	local fmem=$(free -m | grep -E "^Mem:" | awk '{print $NF}')
	row "Free memory" "${fmem}MB of total ${total}MB"
}

temperatures() {
	local sensors=$(find /sys -name 'temp*_input' 2> /dev/null | sort)
	local s= ind=1 t= info=

	[[ -z "$sensors" ]] && return
	for s in $sensors
	do
		t=$(cat $s 2> /dev/null)
		[[ "$t" =~ ^[+-]?([0-9]+\.?|[0-9]*\.[0-9]+)$ && $t -ne 0 ]] || continue
		[[ $ind -gt 1 ]] && info+=", "
		info+="T${ind}=$(echo $t | sed 's/\(.\)..$/\.\1/')°C"
		let $(( ind++ ))
	done
	[[ -n "$info" ]] && row "Temperature" "$info"
}

battery() {
	local info=$(acpi -b 2> /dev/null)
	[[ -z "$info" ]] && return
	row "Battery" "$(echo "$info" | sed -e 's/^Battery \([0-9]*\): /#\1 /' | paste -sd ';' | sed 's/;/; /g')"
}

network() {
	local ips=$(hostname -I 2> /dev/null | xargs)
	[[ -n "$ips" ]] && row "IP address" "$ips"
}

row "System time" "$(date)"
row "Host name" "$(hostname)"
row "Kernel version" "$(uname -r)"
diskfree
network
loadavg
freemem
cpuinfo
temperatures
battery
row "Uptime" "$("$here/uptime.sh")"
