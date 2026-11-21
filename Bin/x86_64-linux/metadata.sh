#! /bin/bash

CDROM="/dev/${1:-sr0}"
LOCK=/dev/shm/metafetch.lock

function lock_wait() {
	while ! mkdir "${LOCK}"
	do
		inotifyd true "${LOCK}:d"
	done
}

function lock_release() {
	rmdir "${LOCK}"
}

function rip_start() {
	/usr/local/bin/cdrip "${CDROM##*/}" start auto
}

function metadata() {
	local update=${1:-true}

	lock_wait
	if $update || [[ ! -e $CDDIR/metadata.env ]] || ( [[ -e $CDDIR/info.env.old ]] && ! diff $CDDIR/info.env.old $CDDIR/info.env >& /dev/null )
	then
		metafetch -m "$MUSICBRAINZ_DISCID" -o "$CDDIR"
		[[ ! -e $CDDIR/metadata.env ]] && freedb.sh "${FREEDB_DISCID}" "${CDTOC}" "$CDDIR/metadata.env"
		if [[ -e $CDDIR/metadata.env && $CDDIR/metadata.env -nt $CDDIR/info.env ]]
		then
			cp /version $CDDIR/metadata.version
			chmod u+w $CDDIR/metadata.version
		fi
	fi

	if [[ -s $CDDIR/metadata.env ]]
	then
		source $CDDIR/metadata.env
		if [[ -z "$GENRE" && -n "$ALLMUSIC" ]]
		then
			GENRE=$(AllMusicGenre "$ALLMUSIC")
			[[ -n "$GENRE" ]] && echo "GENRE=\"$GENRE\"" >> $CDDIR/metadata.env
		fi
		if [[ ! -e $CDDIR/cover.jpg && -n "$ALBUMARTIST" && -n "$ALBUM" ]]
		then
			getcover.sh -a "${ALBUMARTIST}" -r "${ALBUM}" -o $CDDIR
		fi
	fi
	lock_release
}

CDDIR="$(readlink /run/cddad/${CDROM##*/}/audiocd)"
[[ -n "$CDDIR" ]] || exit
RIPSTART=$(sysvar.sh rip_start_mode)
[[ -e $CDDIR/info.env ]] || exit
source $CDDIR/info.env

UPDATE=true
[[ -e $CDDIR/metadata.version ]] && diff /version $CDDIR/metadata.version >& /dev/null && UPDATE=false

if [[ -n "$ACCURATERIP_URL" ]]
then
	(
		ARBIN="${CDDIR}/${ACCURATERIP_URL##*/}"
		ARCSV="${CDDIR}/accuraterip.csv"
		( [[ -e "$ARBIN" ]] && ! $UPDATE ) || wget -q "$ACCURATERIP_URL" -O "$ARBIN" >& /dev/null || exit
		[[ ! -e "$ARCSV" || "$ARCSV" -ot "$ARBIN" ]] && /usr/local/bin/ar2csv "$ARBIN" > "$ARCSV"
		grep -qs "KEYDISC=true" "$CDDIR/accuraterip.env" && exit
		grep -qsv 00000000 "$ARCSV" && echo "KEYDISC=true" >> "$CDDIR/accuraterip.env"
	) &
fi

metadata $UPDATE

if [[ "$RIPSTART" = "always" ]]
then
   rip_start
elif [[ "$RIPSTART" = "metadata" ]]
then
	wait
	[[ -e $CDDIR/metadata.env ]] && rip_start
fi
