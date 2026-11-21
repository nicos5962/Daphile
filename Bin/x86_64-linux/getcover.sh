#! /bin/bash

ua=(
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0"
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Edg/123.0.2420.81"
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 OPR/109.0.0.0"
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 14.4; rv:124.0) Gecko/20100101 Firefox/124.0"
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 OPR/109.0.0.0"
	"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
	"Mozilla/5.0 (X11; Linux i686; rv:124.0) Gecko/20100101 Firefox/124.0"
)

index=$(( $RANDOM % ${#ua[@]} ))
userAgent=${ua[$index]}

while true
do
    case "$1" in
        -a) artist=$2; shift 2 ;;
        -r) album=$2; shift 2 ;;
        -o) outputdir=$2; shift 2 ;;
        *) break ;;
    esac
done
tmp=$(mktemp)
format=$(glyrc cover -u "$userAgent" -a "$artist" -b "$album" -w "$tmp" -j "echo :format:" 2> /dev/null)
if [[ -z "$format" ]]
then
	rm -f $tmp
	exit 1
elif [[ $format = "jpg" ]]
then
	mv $tmp "$outputdir/cover.jpg"
else
	convert $tmp -quality 100 "$outputdir/cover.jpg"
fi

