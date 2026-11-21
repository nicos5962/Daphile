#! /bin/bash
[[ "$USER" = "root" ]] && exec sudo -u user -g user $0 "$@"

mac="$1"
server=$(sed 's,/jsonrpc.js,,' /run/spacd/jsonrpc 2> /dev/null || echo "${LMS_JSONRPC:-http://127.0.0.1:9000/jsonrpc.js}" | sed 's,/jsonrpc.js,,')
mroot="/srv/mediaserver/music"
target="/srv/mediaserver/music/RAM Drive/RAM play cache"
cache_hash_dir="/media/.ramplay_cache_hash_dir"
ramplaydir="/media/ramplay-${mac}.tmpdir"
proglock="${ramplaydir}/proglock"
DSD64=$(( 64 * 44100 ))

export LANG=en_US.UTF-8

lock_wait()
{
	local lockdir="$1"
	while ! mkdir "${lockdir}" >& /dev/null
	do
		inotifyd true "${lockdir}:d" >& /dev/null
	done
}

lock_release()
{
	rmdir "$1"
}

cache_free() {
	df -B 1 "${target}" | tail -n 1 | awk '{free=$4;margin=4*1024*1024;print (free<margin?0:free-margin)}'
}

cache_allocate() {
	local req_space="$1"
	local target_file="$2"
	local wav=
	local free=
	local cache_lock="/dev/shm/ramplay-cache.lock"

	lock_wait "${cache_lock}"

	free=$(cache_free)
	if [[ ${free} -lt ${req_space} ]]
	then
		
		local wavlist=$(mktemp --tmpdir=/dev/shm)
		find "${target}" -type f -name \*.wav -exec stat -c"%Y %n" {} \; | sort -n | cut -f 2- -d ' ' > "${wavlist}"
		local blacklist=$(mktemp --tmpdir=/dev/shm)

		cat $(ls /var/daphile/mediaserver/cache/clientplaylist_*.m3u | grep -v "clientplaylist_${mac//:/}.m3u") |
			perl -MURI::Escape -e 'while (<>) {print uri_unescape($_);}' | 
			sed 's,^tmp://,,' |
			grep -hE "^${target}/" > "${blacklist}"
		cat /dev/shm/ramplay-*.m3u >> "${blacklist}"
		
		while read wav
		do
			grep -qsxF "${wav}" "${blacklist}" && continue
			rm -f "${wav}"
			free=$(cache_free)
			[[ ${free} -gt ${req_space} ]] && break
		done < "${wavlist}"

		rm -f "${wavlist}" "${blacklist}"
		#
		# Remove empty (or containing only cover.jpg) directories
		#
		local ls= dir=
		find "${target}" -depth -type d |
			while read dir
			do
				grep -qsF "${dir}" /dev/shm/ramplay-*.m3u* && continue
				ls=$(ls -A "${dir}")
				[[ "${ls}" = "cover.jpg" ]] && rm -f "${dir}/cover.jpg"
				rmdir "${dir}" >& /dev/null
			done
		
		find "${cache_hash_dir}" -type l ! -exec test -e {} \; -exec rm {} \;
		
		if [[ ${free} -lt ${req_space} ]]
		then
			echo "Failed to free required space (${req_space} vs. ${free})"
			lock_release "${cache_lock}"
			return 1
		fi

	fi
	fallocate -l "${req_space}" "${target_file}"
	lock_release "${cache_lock}"
}

url2hash() {
	local url="$1"

	local hash=$(echo "${mac}${url#*://}" | md5sum | awk '{print $1}')
	echo "${cache_hash_dir}/${hash}"
}

progress() {
	local output="$1"

	while read value
	do
		[[ -n "${value}" ]] && flock "${proglock}" echo "$value" > "${output}"
	done
}

cancel_exit() {
	grep -qs play "${ramplaydir}/MODE" && jsonrpc $mac pause 0
	
	if [[ -n "$pidlist" ]]
	then
		for pid in $pidlist
		do
			pkill -P $pid
		done
		wait $pidlist
	fi
	rm -rf "${ramplaydir}" "${playlist}" "${playlist}.new"
	exit
}

function select_rate() {
	local rate="$1"
	local rates="$2"
	local type="${3:-pcm}"
	local orate=${rates%%:*}
	local dist= min=
	
	for r in ${rates//:/ }
	do
		[[ "$r" =~ ^[0-9]+$ && $r -gt 0 ]] || continue
		[[ "$type" = "pcm" && $r -ge $DSD64 ]] && continue
		[[ "$type" = "dsd" && $r -lt $DSD64 ]] && continue
		if [[ $(( rate % r )) -eq 0 ]]
		then
			dist=$(( rate / r ))
			if [[ -z "$min" || $dist -lt $min ]]
			then
				min=$dist
				orate=$r
			fi
		elif [[ $(( r % rate )) -eq 0 ]]
		then
			dist=$(( r / rate ))
			if [[ -z "$min" || $dist -le $min ]]
			then
				min=$dist
				orate=$r
			fi
		fi
	done
	
	echo "${orate}"
}

convert_files() {
	
	local ind= url=
	local -a start
	local -a stop
	local -a file
	local -a type
	local -a bits
	local -a album
	local -a title
	local -a artist
	local -a year
	local -a tracknum
	local -a genre
	local -a albumartist
	local -a cachehash
	local -a output_format
	local targetname= timespan= ext=

	local req= player_rates= usedop= pcm2dsd_rate= maxbits=
	player_rates=$(jsonrpc ${mac} playerpref plugin.daphile:rates \? | jq -r '.result._p2')
	usedop=$(jsonrpc ${mac} playerpref plugin.daphile:usedop \? | jq -r '.result._p2')
	pcm2dsd_rate=$(jsonrpc ${mac} playerpref plugin.daphile:pcm2dsd_rate \? | jq -r '.result._p2')
	maxbits=$(jsonrpc ${mac} playerpref plugin.daphile:maxbits \? | jq -r '.result._p2')
	[[ ${maxbits:-0} -lt 24 ]] && maxbits=24

	for ind in $@
	do
		url="${transcode[$ind]}"
		if [[ -z "$url" ]]
		then
			# To include in cache blacklist
			[[ -n "${newname[$ind]}" ]] && echo "${newname[$ind]}" >> "${playlist}"
			continue
		fi
		file[$ind]=$(echo "${url#*://}" | perl -MURI::Escape -e 'while (<>) {print uri_unescape($_);}')
		
		if [[ "${file[$ind]}" =~ \#[0-9]+(\.[0-9]+)?-[0-9]+(\.[0-9]+)?$ ]]
		then
			stop[$ind]="${file[$ind]##*\#}"
			local t1=$(date -u --date=@${stop[$ind]%-*} +%H:%M:%S.%2N)
			local t2=$(date -u --date=@${stop[$ind]#*-} +%H:%M:%S.%2N)
			local t3=$(echo "${stop[$ind]%-*} ${stop[$ind]#*-}" | awk '{printf("%f",$2-$1)}')
			timespan="#${t1#00:}-${t2#00:}"
			start[$ind]="-s ${stop[$ind]%-*}"
			stop[$ind]="-d ${t3}"
			file[$ind]="${file[$ind]%\#*}"
		fi
		
		[[ -s "${file[$ind]}" ]] || continue
		
		#
		# Get song info
		#
		local songinfo=$(jsonrpc songinfo 0 100 url:${url} tags:acdIjlogtyxTAalbumartist | jq -c '.result.songinfo_loop[]')

		local remote=$(echo "$songinfo" | jq -r '.remote|numbers')
		[[ "${remote}" -eq 1 && "${url:0:6}" != "tmp://" ]] && continue

		local coverid=$(echo "$songinfo" | jq -r '.coverid|strings')
		local coverart=$(echo "$songinfo" | jq -r '.coverart|strings')
		[[ "${url:0:6}" = "tmp://" && -n "${coverid}" ]] && coverart=1
		
		local duration=$(echo "$songinfo" | jq -r '.duration|numbers')
		local samplerate=$(echo "$songinfo" | jq -r '.samplerate|strings')
		bits[$ind]=$(echo "$songinfo" | jq -r '.samplesize|strings')
		[[ -z "${bits[$ind]}" ]] && bits[$ind]=16

		#
		# Skip corrupted files
		#
		[[ "${samplerate}" =~ ^[0-9]*$ && "${samplerate}" -gt 0 ]] || continue
		[[ "${bits[$ind]}" =~ ^[0-9]*$ && "${bits[$ind]}" -gt 0 ]] || continue

		type[$ind]=$(echo "$songinfo" | jq -r '.type|strings')
		title[$ind]=$(echo "$songinfo" | jq -r '.title|strings')
		artist[$ind]=$(echo "$songinfo" | jq -r '.artist|strings')
		album[$ind]=$(echo "$songinfo" | jq -r '.album|strings')
		genre[$ind]=$(echo "$songinfo" | jq -r '.genre|strings')
		tracknum[$ind]=$(echo "$songinfo" | jq -r '.tracknum|strings')
		year[$ind]=$(echo "$songinfo" | jq -r '.year|strings')
		albumartist[$ind]=$(echo "$songinfo" | jq -r '.albumartist|strings')
		[[ -z "${albumartist}" ]] && albumartist="${artist}"
		#
		#
		#
		ext="${file[$ind]##*.}"
		targetname="${target}${file[$ind]#$mroot}"
		targetname="${targetname%.*}"
		[[ -n "${timespan}" ]] && targetname+=" ${timespan}"

		if [[ -z "${player_rates}" || "${player_rates}" = "null" || ":${player_rates}:" =~ :${samplerate}: ]]
		then
			output_rate="${samplerate}"
		else
			output_rate=$(select_rate "${samplerate}" "${player_rates}")
		fi

		if [[ "${output_rate}" -ge 2822400 ]]
		then
			[[ "${samplerate}" != "${output_rate}" && "${pcm2dsd_rate}" =~ ^[0-9]+$ ]] && output_rate=${pcm2dsd_rate}
			bits[$ind]=1
			if [[ "${usedop}" = "1" ]]
			then
				samplerate=$(( output_rate / 16 ))
				bits[$ind]=24
				targetname+=" ($ext) [DSD$(( output_rate / 44100 ))-DoP].wav"
				output_format[$ind]="dop"
			elif [[ "${output_rate}" -eq "${samplerate}" && "${type}" =~ ^(dsf|dff)$ ]]
			then
				targetname+=" [DSD$(( samplerate / 44100 ))].${type[$ind]}"
				output_format[$ind]="native"
			else
				samplerate="${output_rate}"
				targetname+=" ($ext) [DSD$(( samplerate / 44100 ))].dsf"
				output_format[$ind]="dsf"
			fi
		else
			#
			# PCM WAV output
			#
			if [[ "${output_rate}" -ne "${samplerate}" ]]
			then
				samplerate="${output_rate}"
				bits[$ind]=${maxbits}
			fi
			targetname+=" ($ext) [${samplerate:0:-3}_${bits[$ind]}].wav"
			output_format[$ind]="wav"
		fi
		
		cachehash[$ind]="${newname[$ind]}"
		newname[$ind]="${targetname}"
		mkdir -p "${newname[$ind]%/*}"
		echo "${newname[$ind]}" >> "${playlist}"

		[[ -s "${cachehash[$ind]}" ]] && continue # Same track multiple times on playlist
		
		if [[ -s "${newname[$ind]}" ]]
		then
			ln -sfn "${newname[$ind]}" "${cachehash[$ind]}"
			continue
		fi

		#
		# Allocate cache RAM for output file
		#
		local est_size=$(echo "$samplerate ${bits[$ind]} $duration" | awk '{s=($1*$2*$3/4+16384);printf("%.0f",int(s));}')
		[[ "${output_format[$ind]}" = "native" ]] && est_size=$(stat -c %s "${file[$ind]}")
		local tmpwav[$ind]=$(mktemp --tmpdir="${ramplaydir}" --suffix=".wav" ramplay-track-XXXXXX)
		chmod 644 ${tmpwav[$ind]}
		if ! cache_allocate "${est_size}" ${tmpwav[$ind]}
		then
			rm -f ${tmpwav[$ind]}
			tmpwav[$ind]=""
			continue
		fi
		ln -sfn "${tmpwav[$ind]}" "${cachehash[$ind]}" # To decode each track only once if there exists same track multiple times
		echo "${est_size}" > "${ramplaydir}/track-${ind}.size"
		#
		#
		#
		if [[ "${coverart}" -eq 1 && -n "${coverid}" && ! -s "${newname[$ind]%/*}/cover.jpg" ]]
		then
			cache_allocate $(( 4 * 1024 * 1024 )) "${newname[$ind]%/*}/cover.jpg"
			wget -q "$server/music/${coverid}/cover_500x500.jpg" -O "${newname[$ind]%/*}/cover.jpg"
		fi
		
	done
	touch "${ramplaydir}/decoding"
	#
	#  
	#
	local max_jobs=$(nproc)
	local jobs=
	local mypid=$BASHPID
	for ind in $@
	do

		[[ -n "${tmpwav[$ind]}" ]] || continue
		
		while true
		do
			pidlist=$( ( echo "${pidlist}" ; pgrep -P ${mypid} ) | sort | uniq -d )
			jobs=$(echo "${pidlist}" | wc -w)
			[[ $jobs -lt $max_jobs ]] && break
			[[ -e "${ramplaydir}/STOP" ]] && cancel_exit
			sleep 0.5
		done
		(
			renice -n 10 $BASHPID >& /dev/null

			case "${output_format[$ind]}" in
				"native")
					dd if="${file[$ind]}"
					;;
				"dsf")
					Transcode -F "${type[$ind]}-dsf-ramplay-${mac}" -M -m "${mac}" -f dsf -Z -r ${samplerate} ${start[$ind]} ${stop[$ind]} "${file[$ind]}"
					;;
				"dop")
					Transcode -F "${type[$ind]}-wav-ramplay-${mac}" -M -m "${mac}" -x -f wav -r ${samplerate} ${start[$ind]} ${stop[$ind]} "${file[$ind]}"
					;;
				"wav")
					Transcode -F "${type[$ind]}-wav-ramplay-${mac}" -M -m "${mac}" -f wav -r ${samplerate} ${start[$ind]} ${stop[$ind]} "${file[$ind]}"
					;;
			esac | overwrite - "${tmpwav[$ind]}" | progress "${ramplaydir}/track-${ind}.completed" || rm -f "${tmpwav[$ind]}"
			
			flock "${proglock}" cp "${ramplaydir}/track-${ind}.completed" "${ramplaydir}/track-${ind}.size"
			
			if [[ -f "${tmpwav[$ind]}" ]]
			then
				tnum="${tracknum[$ind]}"
				tnum="${tnum// /}"
				if [[ "${output_format[$ind]}" = "native" ]]
				then
					true
				elif [[ "${newname[$ind]##*.}" = "wav" ]]
				then
					wav_id3 \
						--TALB "${album[$ind]}" \
						--TIT2 "${title[$ind]}" \
						--TPE1 "${artist[$ind]}" \
						$( [[ "${year[$ind]}" -gt 0 ]] && echo '--TYER' "${year[$ind]}" ) \
						$( [[ -n "${tnum}" ]] && echo '--TRCK' "${tnum}" ) \
						--TCON "${genre[$ind]}" \
						--TPE2 "${albumartist[$ind]}" \
						--TENC "RAM play decoder" \
						--TOFN "${file[$ind]}" \
						"${tmpwav[$ind]}"
				elif [[ "${newname[$ind]##*.}" = "dsf" ]]
				then
					dsf_id3 \
						--TALB "${album[$ind]}" \
						--TIT2 "${title[$ind]}" \
						--TPE1 "${artist[$ind]}" \
						$( [[ "${year[$ind]}" -gt 0 ]] && echo '--TYER' "${year[$ind]}" ) \
						$( [[ -n "${tnum}" ]] && echo '--TRCK' "${tnum}" ) \
						--TCON "${genre[$ind]}" \
						--TPE2 "${albumartist[$ind]}" \
						--TENC "RAM play decoder" \
						--TOFN "${file[$ind]}" \
						"${tmpwav[$ind]}"
				fi
				mv "${tmpwav[$ind]}" "${newname[$ind]}"
				ln -sfn "${newname[$ind]}" "${cachehash[$ind]}"
			fi
		) < /dev/null >& /dev/null &
		pidlist+=$'\n'"$!"

	done
	wait ${pidlist}
}

#
# Main
#
mkdir -p "${cache_hash_dir}"

if [[ "$2" = "status" ]]
then
	[[ ! -d "${ramplaydir}" ]] && echo "stop" && exit
	[[ ! -e "${ramplaydir}/decoding" ]] && echo "start" && exit
	total_bytes=$(flock "${proglock}" awk 'BEGIN{s=0}{s+=$1}END{print s}' "${ramplaydir}/"track-*.size)
	completed=$(flock "${proglock}" awk 'BEGIN{s=0}{s+=$1}END{print s}' "${ramplaydir}/"track-*.completed)
	echo $(( completed * 100 / total_bytes ))
	exit
elif [[ "$2" = "stop" ]]
then
	[[ -d "${ramplaydir}" ]] || exit
	touch "${ramplaydir}/STOP"
	pid=$(cat "${ramplaydir}/pid" 2> /dev/null)
	[[ -n "$pid" ]] && kill $pid
	echo "stop"
	exit
fi

connected=$(jsonrpc $mac connected \? | jq -r '.result._connected')
[[ "${connected}" -ne "1" ]] && echo "stop" && exit

if ! mkdir "${ramplaydir}" >& /dev/null
then
	$0 ${mac} status
	exit
fi

tracks=$(jsonrpc $mac playlist tracks \? | jq -r '.result._tracks')
updates=false
removes=false

for i in $(seq 0 $tracks)
do
	#
	# File path
	#
	url=$(jsonrpc $mac playlist path $i \? | jq -r '.result._path')
	if [[ ! "${url}" =~ ^(file|tmp):// ]]
	then
		removes=true
		continue
	fi

	file=$(echo "${url#*://}" | perl -MURI::Escape -e 'while (<>) {print uri_unescape($_);}')
	[[ "${file}" =~ \#[0-9]+(\.[0-9]+)?-[0-9]+(\.[0-9]+)?$ ]] && file="${file%\#*}"
	
	if [[ "${file}" =~ ^"${target}".*\.wav ]]
	then
		newname[$i]="${file}"
	elif [[ -s "${file}" ]]
	then
		newname[$i]=$(url2hash "${url}")
		updates=true
		if [[ -s "${newname[$i]}" ]]
		then
			newname[$i]=$(readlink "${newname[$i]}")
		else
			transcode[$i]="${url}"
		fi
	else
		removes=true
	fi

	$removes && updates=true
done

if ! $updates
then
	rm -rf "${ramplaydir}"
	echo "stop"
	exit 0
fi

(
	trap cancel_exit TERM
	echo $BASHPID > "${ramplaydir}/pid"
	
	jsonrpc $mac mode \? | jq -r '.result._mode' > "${ramplaydir}/MODE"
	jsonrpc -q $mac pause 1
	index=$(jsonrpc $mac playlist index \? | jq -r '.result._index')
	time=$(jsonrpc $mac time \? | jq -r '.result._time')
	
	#
	# timestamp for cache preservation preference
	#
	for ind in $(seq $((index - 1)) -1 0) $(seq $tracks -1 $index)
	do
		touch --no-create "${newname[$ind]}"
	done
	
	playlist=$(mktemp --tmpdir=/dev/shm --suffix=".m3u" ramplay-XXXX)
	
	convert_files $(seq $index $tracks) $(seq 0 $((index - 1)))
	
	cnt=0
	start_index=0
	set_index=false
	for ind in $(seq 0 $tracks)
	do
		[[ "$ind" = "$index" ]] && set_index=true
		[[ -s "${newname[$ind]}" ]] || continue
		echo "${newname[$ind]}"
		if ${set_index}
		then
			start_index=$cnt
			[[ "$index" = "$ind" ]] || time=""
			set_index=false
		fi
		let $(( cnt++ ))
	done > "${playlist}.new"
	
	if [[ -s "${playlist}.new" && ! -e "${ramplaydir}/STOP" ]]
	then
		
		cat "${playlist}.new" | while read line
		do
			echo -n "$line" | perl -MURI::Escape -e 'while (<>) {print uri_escape($_);}' | sed 's,%2F,/,g'
			echo ""
		done | sed 's,^,tmp://,' > "${playlist}"
		
		jsonrpc -q $mac playlist clear
		jsonrpc -q $mac playlist shuffle 0

		while read url
		do
			jsonrpc -q $mac playlist add ${url}
		done < "${playlist}"

		jsonrpc -q $mac playlist index ${start_index}
		[[ -n "${time}" ]] && jsonrpc -q $mac time $time
	fi
	
	rm -rf "${ramplaydir}" "${playlist}.new" "${playlist}"
	
) < /dev/null >& /dev/null &
echo "start"
