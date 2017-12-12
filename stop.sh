#!/usr/bin/env bash
set -x
# BINDIR should point to the psrdada installation
if [ x$BINDIR == x ]; then
  echo "Please set BINDIR"
  exit
fi

echo "TODO, see notes in the script stop.sh"
# TODO:
# * send SIGTERM to the fill_ringbuffer instances
# * clean up the dada_dbdisk; I don't see a way to do it nicely so SIGTERM/SIGKILL it
# * clean up the ringbuffers via 'dada_db -d -k ...'

