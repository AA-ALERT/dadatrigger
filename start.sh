#!/usr/bin/env bash
set -x
# BINDIR should point to the psrdada installation
if [ x$BINDIR == x ]; then
  echo "Please set BINDIR"
  exit
fi

# FITS_TEMPLATES should be set to the directory containing the templates
if [ x$FITS_TEMPLATES == x ]; then
  echo "Please set FITS_TEMPLATES"
  exit
fi

######################################################################
echo "Observation configuration"
######################################################################

# Set the science case: 
# 3: 12500 sampels/1.024 seconds
# 4: 25000 samples/1.024 seconds
SCIENCE_CASE=3

# Set beam type (note, science_mode is derived from this for the I and IQUV data flows)
# TAB: mode 0 (I+TAB) for Stokes I, and mode 1 (IQUV+TAB) for Stokes IQUV
# IAB: mode 2 (I+IAB) for Stokes I, and mode 3 (IQUV+IAB) for Stokes IQUV
BEAM_TYPE=IAB

# Start time of observation
START_STAMP=`date +%s`
UTC_START=`date -u +%Y-%m-%d-%H:%M:%S --date "@${START_STAMP}"`

# Start packet: TODO how was this again? 
START_PACKET=10

# Duration of observation in seconds
DURATION=30

# NOTE: output directories should exist, files are not overwritten
OUTPUT_FULL_IQUV=./output/        # directory
OUTPUT_FULL_I=./output/fulli      # directory plus prefix of filename: /full/path/file -> /full/path/file_01.fil
OUTPUT_REDUCED_I=./output         # directory

# NOTE: full paths to logfiles, directories should exist
LOG_WRITER_FULL_I=./output/log_full_i.txt
LOG_WRITER_FULL_IQVU=./output/log_full_iquv.txt
LOG_WRITER_REDUCED_I=./output/log_reduced_i.txt
LOG_TRIGGER=./output/log_trigger.txt
LOG_NETWORK_I=./output/log_fill_i.txt
LOG_NETWORK_IQUV=./output/log_fill_iquv.txt

######################################################################
# Static config (does not depend on specific observation)
######################################################################

# AMBER uses padding to optimize memory layout. Specifiy padding sizes here:
# note: this should be at least 12500 for science case 3, and 25000 for science case 4
if [ x${SCIENCE_CASE} = x3 ]
then
  SAMPLES_PER_BATCH=12500
  FULL_I_PADDED_SIZE=12588
elif [ x${SCIENCE_CASE} = x4 ]
then
  SAMPLES_PER_BATCH=25000
  FULL_I_PADDED_SIZE=25088
else
  echo "Illegal science case: $SCIENCE_CASE"
  exit -1
fi

if [ x${BEAM_TYPE} = xTAB ]
then
  NTABS=12;
  SCIENCE_MODE_I=0
  SCIENCE_MODE_IQUV=1
elif [ x${BEAM_TYPE} = xIAB ]
then
  NTABS=1;
  SCIENCE_MODE_I=2
  SCIENCE_MODE_IQUV=3
else
  echo "Illegal beam type, cannot derive science mode: $BEAM_TYPE"
fi

# When AMBER indicates there is a possible FRB, full StokesIQUV data in a window around the event
# must be written to disk. Therfore, we need to hold on to old data until it is outside of a possible window
TRIGGER_HISTORY=5 # maximum delay (s) to retain data for

# Network ports for incomming data streams
PORT_I=8001
PORT_IQUV=8002

# main buffer I
# NTABS x NCHANNELS x PADDING bytes
MAINI_KEY=dada
let "MAINI_SIZE = ${NTABS} * 1536 * ${FULL_I_PADDED_SIZE}"
MAINI_COUNT=3

# main buffer IQUV
# NTABS x NCHANNELS x NPOLS x NTIMES bytes
MAINIQUV_KEY=dadc
let "MAINIQUV_SIZE = ${NTABS} * 1536 * 4 * ${SAMPLES_PER_BATCH}"
let "MAINIQUV_COUNT= 3 + ${TRIGGER_HISTORY}"

# disk buffer IQUV
# should hold exaclty one page of the main iquv buffer
DISKIQUV_KEY=dade
DISKIQUV_SIZE=${MAINIQUV_SIZE}
DISKIQUV_COUNT=3

######################################################################
echo "Start the dada_db ring buffers"
######################################################################

# delete ringbuffers TODO: do we really want that? it could accidentally kill another observation
${BINDIR}/dada_db -d -k ${MAINI_KEY}    2>&1 > /dev/null
${BINDIR}/dada_db -d -k ${MAINIQUV_KEY} 2>&1 > /dev/null
${BINDIR}/dada_db -d -k ${DISKIQUV_KEY} 2>&1 > /dev/null

# start buffers
${BINDIR}/dada_db -p -k ${MAINI_KEY}    -n ${MAINI_COUNT}    -b ${MAINI_SIZE}    -r 2
${BINDIR}/dada_db -p -k ${MAINIQUV_KEY} -n ${MAINIQUV_COUNT} -b ${MAINIQUV_SIZE} -r 1
${BINDIR}/dada_db -p -k ${DISKIQUV_KEY} -n ${DISKIQUV_COUNT} -b ${DISKIQUV_SIZE} -r 1

######################################################################
echo "Start the dada_dbevent for FRB triggers"
######################################################################

# TASK: Respond to FRB triggers
# dada_dbevent [options] inkey outkey
# inkey       input hexadecimal shared memory key
# outkey      input hexadecimal shared memory key
# -b percent  delay procesing of the input buffer up to this amount [default 80 %]
# -t delay    maximum delay (s) to retain data for [default 60s]
# -h          print this help text
# -p port     port to listen for event commands [default 30000]
# -v          be verbose
${BINDIR}/dada_dbevent ${MAINIQUV_KEY} ${DISKIQUV_KEY} -v -t ${TRIGGER_HISTORY} 2> ${LOG_TRIGGER} &
# NOTE: multilog writes to stderr here

######################################################################
echo  "Start AMBER"
######################################################################

# TASK: build example trigger
let "EVENT_START_STAMP = ${START_STAMP} + 20"
let "EVENT_END_STAMP = ${START_STAMP} + 22"
EVENTSTART=`date -u +%Y-%m-%d-%H:%M:%S --date "@${EVENT_START_STAMP}"`
EVENTEND=`date -u +%Y-%m-%d-%H:%M:%S --date "@${EVENT_END_STAMP}"`

# A trigger contains:
# N_EVENTS %i
# YYYY-MM-DD-HH:MM:SS (start of observation, here UTC_START)
# QUIT | YYYY-MM-DD-HH:MM:SS fraction YYYY-MM-DD-HH:MM:SS fraction DM SNR  (start and end of event)

# note that start time is:
#  * converted to a byte index using BYTES_PER_SECOND and observation UTC_START
#  * rounded down to RESOLUTION
# and end time is:
#  * converted to a byte index using BYTES_PER_SECOND and observation UTC_START
#  * rounded up to RESOLUTION
echo "N_EVENTS 1"    > trigger
echo "${UTC_START}" >> trigger
echo "${EVENTSTART} 0 ${EVENTEND} 0 2.0 1.0" >> trigger

# TASK: connect AMBER to the ringbuffer

######################################################################
echo "Start the data writers"
######################################################################

# TASK: Write full I to disk in filterbank format
# dadafilterbank [options]
#  -c <science case>
#  -m <science mode>
#  -k <hexadecimal key>
#  -l <logfile>
#  -b <padded_size>
#  -n <filename prefix for dumps>
${BINDIR}/dadafilterbank -k ${MAINI_KEY} -l ${LOG_WRITER_FULL_I} -n ${OUTPUT_FULL_I} &

# TASK: Write reduced (1-bit, downsampled) I to disk in FITS format
# dadafits [options]
# -k <hexadecimal key>
# -l <logfile>
# -t <template>
# -d <output_directory>
# -S <synthesized beam table>
# -s <synthesize these beams>
${BINDIR}/dadafits -k ${MAINI_KEY} -l ${LOG_WRITER_REDUCED_I} -t ${FITS_TEMPLATES} -d ${OUTPUT_REDUCED_I} &

# TASK: Write full IQUV data to disk on triggers
# dada_dbdisk [options]
#  -b <core>  bind process to CPU core TODO
#  -k         hexadecimal shared memory key  [default: dada]
#  -D <path>  add a disk to which data will be written
#  -o         use O_DIRECT flag to bypass kernel buffering
#  -W         over-write exisiting files
#  -s         single transfer only TODO
#  -t bytes   set optimal bytes TODO
#  -z         use zero copy transfers TODO
#  -d         run as daemon
${BINDIR}/dada_dbdisk -k ${DISKIQUV_KEY} -D ${OUTPUT_FULL_IQUV} 2> ${LOG_WRITER_FULL_IQVU} &
# NOTE: multilog writes to stderr here

# TASK: 8 bits tracking beams per pulsar TODO

######################################################################
echo "Connect dada_db ringbuffers to the network"
######################################################################

# TASK: create dada header file for the Stokes I buffer
#  * set the UTC_START in the header
#  * set bytes per second in the header correctly 462422016 / 1.024 = 451584000
#  * set the observation RESOLUTION to the page size 462422016
let "BPS = ${MAINI_SIZE} * 1000 / 1024"

cp header                                        ./header_i_with_utc
echo "SAMPLES_PER_BATCH ${SAMPLES_PER_BATCH}" >> ./header_i_with_utc
echo "UTC_START ${UTC_START}"       >>           ./header_i_with_utc
echo "RESOLUTION  ${MAINI_SIZE}"    >>           ./header_i_with_utc
echo "BYTES_PER_SECOND  ${BPS}"     >>           ./header_i_with_utc

# TASK: create dada header file for the Stokes IQUV buffer
#  * set the UTC_START in the header
#  * set bytes per second in the header correctly 462422016 / 1.024 = 451584000
#  * set the observation RESOLUTION to the page size 462422016
let "BPS = ${MAINIQUV_SIZE} * 1000 / 1024"

cp header                                        ./header_iquv_with_utc
echo "SAMPLES_PER_BATCH ${SAMPLES_PER_BATCH}" >> ./header_iquv_with_utc
echo "UTC_START ${UTC_START}"       >>           ./header_iquv_with_utc
echo "RESOLUTION  ${MAINIQUV_SIZE}" >>           ./header_iquv_with_utc
echo "BYTES_PER_SECOND  ${BPS}"     >>           ./header_iquv_with_utc

# TASK: listen to a network port, and copy incomming UDP packets to the Stokes I ringbuffer
# fill_ringbuffer [options]
# -h <header file>
# -k <hexadecimal key>
# -c <science case>
# -m <science mode>
# -s <start packet number>
# -d <duration (s)>
# -p <port>
# -l <logfile>
#${BINDIR}/fill_ringbuffer -h  ./header_i_with_utc -k ${MAINI_KEY} -c ${SCIENCE_CASE} -m ${SCIENCE_MODE_I} -d ${DURATION} -b ${FULL_I_PADDED_SIZE} -l ${LOG_NETWORK_I} -s ${START_PACKET} -p ${PORT_I} &

${BINDIR}/fill_fake  -h  ./header_i_with_utc -k ${MAINI_KEY} -c ${SCIENCE_CASE} -m ${SCIENCE_MODE_I} -d ${DURATION} -b ${FULL_I_PADDED_SIZE} -l ${LOG_NETWORK_I} &

# TASK: listen to a network port, and copy incomming UDP packets to the Stokes IQUV ringbuffer
# fill_ringbuffer [options]
# -h <header file>
# -k <hexadecimal key>
# -c <science case>
# -m <science mode>
# -s <start packet number>
# -d <duration (s)>
# -p <port>
# -l <logfile>
#${BINDIR}/fill_ringbuffer -h  ./header_iquv_with_utc -k ${MAINIQUV_KEY} -c ${SCIENCE_CASE} -m ${SCIENCE_MODE_IQUV} -d ${DURATION} -b ${FULL_I_PADDED_SIZE} -l ${LOG_NETWORK_IQUV} -s ${START_PACKET} -p ${PORT_IQUV} &

${BINDIR}/fill_fake  -h ./header_iquv_with_utc -k ${MAINIQUV_KEY} -c ${SCIENCE_CASE} -m ${SCIENCE_MODE_IQUV} -d ${DURATION} -b ${FULL_I_PADDED_SIZE} -l ${LOG_NETWORK_IQUV} &




## pull a trigger
cat trigger | ncat localhost 30000
