#!/usr/bin/env bash

# BINDIR should point to the psrdada installation and the fill_fake program from the fill_ringbuffer repo
if [ x$BINDIR == x ]; then
  echo "Please set BINDIR"
  exit
fi

export TESTKEY=dada
export DUMPKEY=dadc

UTC_START=`date -u +%Y-%m-%d-%H:%M:%S --date "10 seconds"`
EVENTSTART=`date -u +%Y-%m-%d-%H:%M:%S --date "20 seconds"`
EVENTEND=`date -u +%Y-%m-%d-%H:%M:%S --date "22 seconds"`

echo "Starting with UTC_START=$UTC_START"

# A trigger contains:
# N_EVENTS %i
# YYYY-MM-DD-HH:MM:SS                                                     # UTC_START of observation
# QUIT | YYYY-MM-DD-HH:MM:SS fraction YYYY-MM-DD-HH:MM:SS fraction DM SNR # UTC START fractional_seconds UTC_END fractional_seconds DM SNR

# note that start time is:
#  * converted to a byte index using BYTES_PER_SECOND and observation UTC_START
#  * rounded down to RESOLUTION
# and end time is:
#  * converted to a byte index using BYTES_PER_SECOND and observation UTC_START
#  * rounded up to RESOLUTION
echo "N_EVENTS 1"    > trigger
echo "${UTC_START}" >> trigger
echo "${EVENTSTART} 0 ${EVENTEND} 0 2.0 1.0" >> trigger

# dada_dbevent [options] inkey outkey
# inkey       input hexadecimal shared memory key
# outkey      input hexadecimal shared memory key
# -b percent  delay procesing of the input buffer up to this amount [default 80 %]
# -t delay    maximum delay (s) to retain data for [default 60s]
# -h          print this help text
# -p port     port to listen for event commands [default 30000]
# -v          be verbose
${BINDIR}/dada_dbevent ${TESTKEY} ${DUMPKEY} -v -t 5 &

# fill it with fake data
# NOTE: 
#  * set the UTC_START in the header
#  * set bytes per seconde in the header correctly 462422016 / 1.024 = 451584000
#  * set the observation RESOLUTION to the page size 462422016
cp header                             ./header_with_utc
echo "UTC_START ${UTC_START}"      >> ./header_with_utc
echo "RESOLUTION  462422016"       >> ./header_with_utc
echo "BYTES_PER_SECOND  451584000" >> ./header_with_utc


${BINDIR}/fill_fake  -h  ./header_with_utc -k ${TESTKEY} -c 4 -m 0 -d 10000 -b 25088 -l log 
