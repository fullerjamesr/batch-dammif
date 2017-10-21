#!/bin/bash

# Check for, and require, the existence of the "enhanced" getopt
#  Credit: https://stackoverflow.com/a/29754866
getopt --test > /dev/null
if [[ $? -lt 4 ]]; then
    echo "$0: This script requires the new GNU getopt"
    exit 2
fi

# The user must specify the input gnom file
# The user may specify the .in file from which to read parameters (default: None, behavior depends on mode switch
#					   the mode to start in (slow, or interactive [requires screen]) if no input parameter file is given
#                      the path to the dammif executable (default: asssume dammif is in PATH)
#					   the prefix for the dammif output (default: The name of the GNOM file)
#                      the number of dammif instances to start (default: 1)
OPTIONS=i:b:p:n:m:
LONGOPTIONS=in:,bin:,prefix:,num:,mode:
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name="$0" -- "$@")
if [[ $? -ne 0 ]]; then
	exit 2
fi
eval set -- "$PARSED"

DAMMIFPATH="dammif"
NUMINSTANCES=1
MODE="SLOW"
while true; do
	case "$1" in
		-n|--num)
			NUMINSTANCES="$2"
			shift 2
			;;
		-i|--in)
			INFILE="$2"
			shift 2
			;;
		-b|--bin)
			DAMMIFPATH="$2"
			shift 2
			;;
		-p|--prefix)
			PREFIX="$2"
			shift 2
			;;
		-m|--mode)
			MODE="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo "Unrecognized option -- why was this not caught by getopt?"
			exit 2
			;;
	esac
done

# Set options/defaults as needed and check the files exist
# Credit for the check of var existence: https://stackoverflow.com/a/13864829
#	GNOMFILE must be specified and be a real file
if [[ $# -eq 1 ]]; then
    GNOMFILE=$1
else
	echo "$0: Expected a single argument representing the input GNOM file."
	exit 2
fi
if [[ ! -f "$GNOMFILE" ]]; then
	echo "$0: $GNOMFILE does not exist or is not a file"
	exit 2
fi
#	By default, the prefix is the same as the GNOM file name
#	The prefix also tells dammif the output directory
if [[ -z ${PREFIX+x} ]]; then
	PREFIX=${GNOMFILE%.out}
fi
# infile, if provided, should also be real
if [[ ! -z ${INFILE+x} ]] && [[ ! -f "$INFILE" ]]; then
	echo "$0: Input parameter file does not exist or is not a file"
	exit 2
fi
# Mode must be one of [SLOW, INTERACTIVE] if INFILE is not specified
if [[ -z ${INFILE+x} ]] && [[ "$MODE" != "slow" ]] && [[ "$MODE" != "interactive" ]]; then
	echo "$0: in the absence of an input parameter file, MODE must be either slow or interactive"
	exit 2
fi
# Check for dammif
#  Credit: https://stackoverflow.com/a/677212
command -v "$DAMMIFPATH" > /dev/null 2>&1 || { echo "$0: failed to find dammif executable"; exit 2; }

LAUNCHED=0
i=1
while [[ $LAUNCHED -lt $NUMINSTANCES ]]; do
	# Find the next $PREFIX-$i that is not occupied
	while [[ -f "$PREFIX-$i.log" ]]; do
		echo "$PREFIX-$i.log exists, skipping this index..."
		let i=i+1
	done
	# If no input file, launch dammif instances depending on the screen/interactive switch
	if [[ -z ${INFILE+x} ]]; then
		if [[ "$MODE" = "interactive" ]]; then
			echo "Starting run $PREFIX-$i in a screen session, which will await user input..."
			# The -d -m flags start screen sessions silently without bringing them to focus.
			#	-S takes the first argument as the name of the session.
			screen -d -m -S $PREFIX-$i $DAMMIFPATH --prefix=$PREFIX-$i --mode=interactive $GNOMFILE
		else
			echo "Starting $PREFIX-$i with default (slow mode) parameters..."
			$DAMMIFPATH --prefix=$PREFIX-$i --omit-solvent --mode=slow $GNOMFILE > /dev/null &
			# sleep to allow the new dammif instance to write files before looping
			sleep 2s
		fi
	# else (there is an input specified), then start a dammif run using it
	else
		echo "Starting $PREFIX-$i using $INFILE..."
		# In this case the user doesn't need to set any further options, so dammif can be
		# started without terminal I/O. BUT we do need to redo the random seed each time.
		RAND=$((RANDOM*54933))
		sed -i "7 s/[0-9][0-9]*/$RAND/" $INFILE
		# I have found a need to sleep for a moment to ensure sed's changes to the file
		# are registered over slow network drives before launching dammif
		sleep 2s
		$DAMMIFPATH --prefix=$PREFIX-$i --omit-solvent --mode=interactive $GNOMFILE < $INFILE > /dev/null &
	fi
	let LAUNCHED=LAUNCHED+1
	let i=i+1
done
