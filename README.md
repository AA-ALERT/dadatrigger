Dadatrigger
===========

This code is written for the AA-Alert project.
(c) 2017 Jisk Attema, Netherlands eScience Center, ASTRON


Based on the PSRdada software.


Selectively dumping parts of a data stream with dada\_dbevent
============================================================

Setup:

1. Main ringbuffer (that is being filled by fi. the fill\_ringbuffer program). This also serves as a cache; ie it should hold on to data until it is out of the dumping window
2. dada\_dbevent. Listens to triggers on a network port (localhost:30000 by default), and when triggered copies data to the disk buffer
3. Disk ringbuffer. Stageing place to write to disk
4. dada\_dbdisk. Dumps all data in the disk buffer. Prepends the header block.

Triggering
==========

A trigger is a text file containing:
  * *N_EVENTS* followed by an integer number indicating the number of events in the trigger
  * On the next line, the start time of the observation in UTC, in the form YYYY-MM-DD-HH:MM:SS

then per event a single line with (space separated):
  * Event start as YYYY-MM-DD-HH:MM:SS
  * seconds fraction for start time as floating point number
  * Event end as YYYY-MM-DD-HH:MM:SS
  * seconds fraction for end time as floating point number
  * DM  floating point number, not used further.
  * SNR floating point number, not used further.

or:
  * *QUIT*

A trigger can be send using fi: *cat trigger | ncat localhost 30000*


Output
======

Events overlapping in time are merged to a single event.
The header block from the main ringbuffer is then prepended to the datastream, and the buffers are dumped to disk.
Events are stored one per file.

The to map times to bytes, the *BYTES_PER_SECOND* is used together with *UTC_START*. These must be defined in the main ringbuffer header.
The resulting byte index then rounded to the neareset multiple of *RESOLUTION* (also from the ringbuffer header).
It is rounded down for start, and up for end times.
We use this to make sure we only dump complete ringbuffer pages.


Usage
=====

1. Setup the ringbuffers with the *setup_buffers.sh* script
2. Get data flowing by running *setup.sh*
3. Trigger an event by sending message to the dada\_dbevent program (see the explanation above, and the generated file *trigger*)


Replaying an event
===================

The event (ie. the dumped data) can be replayed, for further processing.
1. create a ringbuffer with exactly the same page size
2. connect a  *dada_diskdb* to the ringbuffer as writer and pass it the file(s):
    dada_diskdb -k <key> -f <file1> [-f <file2> ...]
3. connect your processing script to the ringbuffer as a reader

Notes
=====

1. *dada_dbdisk* can only accept 1024 input files. Configure *dada_dbdisk* to write bigger files if you run into this limit. Set *FILE_SIZE* to 384000000.0


