#!/usr/bin/env bash

# BINDIR should point to the psrdada installation
if [ x$BINDIR == x ]; then
  echo "Please set BINDIR"
  exit
fi

export TESTKEY=dada
export DUMPKEY=dadc

# main buffer

# delete old ringbuffer
${BINDIR}/dada_db -d -k ${TESTKEY}

# start a new ringbuffer with NTABS x NCHANNELS x 25088 bytes = 460800000
${BINDIR}/dada_db -p -k ${TESTKEY} -n 3 -b 462422016 -r 1

# disk buffer

# delete old ringbuffer
${BINDIR}/dada_db -d -k ${DUMPKEY}

# start a new ringbuffer with NTABS x NCHANNELS x 25088 bytes = 460800000
${BINDIR}/dada_db -p -k ${DUMPKEY} -n 3 -b 462422016

# start a dbdisk to do the actual writing
# dada_dbdisk [options]
#  -b <core>  bind process to CPU core
#  -k         hexadecimal shared memory key  [default: dada]
#  -D <path>  add a disk to which data will be written
#  -o         use O_DIRECT flag to bypass kernel buffering
#  -W         over-write exisiting files
#  -s         single transfer only
#  -t bytes   set optimal bytes
#  -z         use zero copy transfers
#  -d         run as daemon
${BINDIR}/dada_dbdisk -k ${DUMPKEY} -D /home/jiska/Code/AA/src/dadatrigger/output
