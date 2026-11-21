#! /bin/bash

function daphile_version() {

	local build=$(cat /proc/cmdline | sed 's/.*daphile=//' | awk '{print $1}')

	if [[ "${build:0:2}" != "fw" ]]
	then
		build=$(cat /version)
		if [[ "${build:0:2}" != "fw" ]]
		then
			echo "Unknown"
			return
		fi
	fi

	local arch="$HOSTTYPE"
	uname -v | grep -qs "PREEMPT[ _]RT" && arch+="-rt"

	if [[ "$(sysvar.sh fw_stable)" = "true" ]]
	then
		echo "${build:2:2}.${build:4:2}$(sysvar.sh fw_stable_minor)-${arch}"
	else
		echo "${build:2:2}.${build:4:2}-b${build:6}-${arch}"
	fi
}

echo "Daphile version: $(daphile_version)"
echo ""
spacdir=/run/spacd
for x in /sys/class/sound/card*
do 
    [[ -L "$x" ]] || continue
    cardnum=${x#*card}
    module=$(readlink $x/device/driver | awk -F / '{print $NF}')
    [[ $module = snd_dummy || $module = snd_aloop ]] && continue
    cardname=$(egrep ^CARDNAME= $spacdir/info/$cardnum | cut -d = -f 2-)
    [[ -z "$cardname" ]] && cardname="Unnamed"    
    syspath=$(readlink -f "$x")
    echo "Card #$cardnum: $cardname"
    if [[ "$syspath" =~ "usb" ]]
    then
        serid=$(cat "$syspath/../../../serial" 2> /dev/null)
        [[ -z "$serid" ]] || echo "  Serial: $serid"
        echo "  Driver: $(readlink -f "$syspath/../../driver" | awk -F / '{print $NF}')"
        busnum=$(cat "$syspath/../../../../busnum")
        devnum=$(cat "$syspath/../../../devnum")
        usbbus=$(printf "%3.3d/%3.3d" "$busnum" "$devnum")
        devid="$(cat $syspath/../../../idVendor 2> /dev/null):"
        devid="${devid}$(cat $syspath/../../../idProduct 2> /dev/null)"
        syspath2=${syspath%%/usb*}
        echo "  USB BUS: $usbbus"
        module=$(readlink $syspath2/driver | awk -F / '{print $NF}')
        echo "  USB driver: $module"
        [[ "$module" =~ ^.hci[-_] ]] && module="${module:0:4}_hcd"
    elif [[ "$syspath" =~ /fw[0-9] ]]
    then
        serid=$(cat "$syspath/../../../serial" 2> /dev/null)
        [[ -z "$serid" ]] || echo "  Serial: $serid"
        echo "  Driver: $(readlink -f "$syspath/../../driver" | awk -F / '{print $NF}')"
        devid="$(cat $syspath/../../../vendor 2> /dev/null):"
        devid="${devid}$(cat $syspath/../../../model 2> /dev/null)"
        syspath2=${syspath%%/fw*}
        module=$(readlink $syspath2/driver | awk -F / '{print $NF}')
        echo "  Firewire driver: $module"
    else
        tp="$syspath/device"
        devid="$(cut -c 3- $tp/vendor 2> /dev/null):$(cut -c 3- $tp/device 2> /dev/null)"
        [[ $devid = ":" ]] && continue
        module=$(readlink $syspath/device/driver | awk -F / '{print $NF}')
        echo "  Driver: $module"
    fi
    irq=$(awk '{print $1}' $spacdir/c/${cardnum}/irqinfo)
    irqpid=$(awk '{print $2}' $spacdir/c/${cardnum}/irqinfo)
    irqpry=$(ps h -p $irqpid -o rtprio 2> /dev/null | sed 's/ //g')
    echo "  Device ID: $devid"
    echo "  IRQ: $irq (PRY:$irqpry)"

    if [[ -s "/run/spacd/c/${cardnum}/home/mixer.conf" ]]
    then
        echo "  Mixer controls:"
        echo "    Config:"
        sed 's/^/      /' "/run/spacd/c/${cardnum}/home/mixer.conf"
        echo "    Contents:"
        amixer -c ${cardnum} scontents | sed 's/^/      /'
        echo "    JSON='$(amixer -c ${cardnum} json)'"
    else
        echo "  Mixer controls: none"
    fi

	if [[ -s "$spacdir/info/${cardnum}.usbinfo" ]]
	then
        echo "  USB info:"
		sed -e 's,^,    ,' "$spacdir/info/${cardnum}.usbinfo"
	fi
		
    for d in /sys/class/sound/pcmC${cardnum}D*p
    do
        [[ -e "$d" ]] || continue
        devnum=$(echo $d | sed 's/.*pcmC[0-9]*D\([0-9]\).*/\1/')
        cat $spacdir/info/${cardnum}.${devnum} 2> /dev/null | sed s,=,=\', | sed s,\$,\', > /dev/shm/acap.log
        DEVNAME=""
        RATES=""
        FORMAT=""
        DSDFMT=""
        PLAYERPID="$(cat /run/spacd/c/${cardnum}/d/${devnum}/pid 2> /dev/null)"
        [[ -n "${PLAYERPID}" ]] && PLAYERCOMM="$(cat /proc/${PLAYERPID}/comm)" || PLAYERCOMM=""
        . /dev/shm/acap.log
        if [[ -n "$DEVNAME" ]]
        then
            if [[ -e "/run/spacd/c/${cardnum}/home/enabled/${devnum}" ]]
            then
                ENABLED=" (enabled)"
            else
                ENABLED=""
            fi
            echo "  Device #${devnum}${ENABLED}: $DEVNAME"
            [[ "${PLAYERCOMM}" = "jive" ]] && PLAYERCOMM=squeezeplay
            [[ -n "${PLAYERCOMM}" ]] && echo "    Player process: ${PLAYERCOMM} (PID:${PLAYERPID})"
            echo "    Rates: $RATES"
            echo -n "    Format: $FORMAT"
            [[ -n "$DSDFMT" ]] && echo -n " (DSD: ${DSDFMT#DSD_})"
            echo ""
            if [[ -n "$ENABLED" ]]
            then
                echo "    Settings:"
                grep -vE '^PLAYER=' $spacdir/c/${cardnum}/home/volume.conf |
					sed -e 's/^/      /' -e "s/='\(.*\)'$/=\1/" -e "s/\([^=]*\)=\(.*\)$/\L\1\E='\2'/" -e "s/='\([0-9]*\)'$/=\1/"
            fi
        else
            echo "  Device #$devnum: $(acap -C $cardnum -D $devnum 2> /dev/null | grep DEVNAME= | cut -f 2- -d =), NOT SUPPORTED"
        fi
		stream="/proc/asound/card${cardnum}/stream${devnum}"
		if [[ -e "${stream}" ]]
		then
                echo "    Proc asound stream${devnum}:"
				sed -e '/^\s*$/d' -e 's,^,      ,' "${stream}"
		fi
    done
    echo ""
done
echo "Interrupts:"
sed 's/^/  /' /proc/interrupts
echo ""
echo "Realtime priorities:"
ps -eLo rtprio,cls,pid,pri,nice,comm | grep F\\F | sort -r 
rm -f /dev/shm/acap.log
echo ""
echo "aplay info:"
aplay -l
