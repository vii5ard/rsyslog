#!/bin/bash
# This test creates multiple symlinks (all watched by rsyslog via wildcard)
# chained to target files via additional symlinks and checks that all files
# are recorded with correct corresponding metadata (name of symlink 
# matching configuration).
# This is part of the rsyslog testbench, released under ASL 2.0
. ${srcdir:=.}/diag.sh init
. $srcdir/diag.sh check-inotify
export IMFILEINPUTFILES="10"
export IMFILELASTINPUTLINES="3"
export IMFILECHECKTIMEOUT="60"

# generate input files first. Note that rsyslog processes it as
# soon as it start up (so the file should exist at that point).
generate_conf
add_conf '
# comment out if you need more debug info:
	global( debug.whitelist="on"
		debug.files=["imfile.c"])
module(load="../plugins/imfile/.libs/imfile"
       mode="inotify" normalizePath="off")
input(type="imfile" File="./'$RSYSLOG_DYNNAME'.input-symlink.log" Tag="file:"
	Severity="error" Facility="local7" addMetadata="on")
input(type="imfile" File="./'$RSYSLOG_DYNNAME'.input.*.log" Tag="file:"
	Severity="error" Facility="local7" addMetadata="on")
template(name="outfmt" type="list") {
	constant(value="HEADER ")
	property(name="msg" format="json")
	constant(value=", filename: ")
	property(name="$!metadata!filename")
	constant(value=", fileoffset: ")
	property(name="$!metadata!fileoffset")
	constant(value="\n")
}
if $msg contains "msgnum:" then
	action( type="omfile" file="'${RSYSLOG_OUT_LOG}'" template="outfmt")
'

imfilebefore=$RSYSLOG_DYNNAME.input-symlink.log
./inputfilegen -m 1 > $imfilebefore
mkdir $RSYSLOG_DYNNAME.targets

# Start rsyslog now before adding more files
startup

for i in `seq 2 $IMFILEINPUTFILES`;
do
	cp $imfilebefore $RSYSLOG_DYNNAME.targets/$i.log
	ln -s $RSYSLOG_DYNNAME.targets/$i.log rsyslog-link.$i.log
	ln -s rsyslog-link.$i.log $RSYSLOG_DYNNAME.input.$i.log
	imfilebefore="$RSYSLOG_DYNNAME.targets/$i.log"
	# Wait little for correct timing
	./msleep 50
done

# Content check with timeout
content_check_with_count "HEADER msgnum:00000000:" $IMFILEINPUTFILES $IMFILECHECKTIMEOUT

./inputfilegen -m $IMFILELASTINPUTLINES > $RSYSLOG_DYNNAME.input.$((IMFILEINPUTFILES + 1)).log
ls -l $RSYSLOG_DYNNAME.input.* rsyslog-link.* $RSYSLOG_DYNNAME.targets

# Content check with timeout
content_check_with_count "input.11.log" $IMFILELASTINPUTLINES $IMFILECHECKTIMEOUT

shutdown_when_empty # shut down rsyslogd when done processing messages
wait_shutdown        # we need to wait until rsyslogd is finished!
exit_test
