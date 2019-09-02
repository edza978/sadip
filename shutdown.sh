#!/bin/sh
# Script tomado de:
# https://htcondor-wiki.cs.wisc.edu/index.cgi/wiki?p=HowToShutdownAnIdleMachine
#
# We start out trying to determine if this shutdown was voluntary or not.
# In this example, we don't do anything useful with this information, so
# you can skip it if you like.
#
# I'm not sure if /sbin/runlevel is available on systemd systems, so you
# check to make sure that this is normally nonzero and zero when shutting down.
SHUTDOWN=`/sbin/runlevel | /usr/bin/awk '{print $2}'`
SHUTDOWN_MESSAGE='because instance is being terminated'
if [ ${SHUTDOWN} -ne 0 ]; then
   SHUTDOWN_MESSAGE='for lack of work'
fi
# The following line is probably AWS-specific; you can omit it and the
# ${INSTANCE_ID} from the following line entirely.
INSTANCE_ID=$(/usr/bin/curl -s http://169.254.169.254/latest/meta-data/instance-id)
MESSAGE="$(/bin/date) Instance ${INSTANCE_ID} shutting down ${SHUTDOWN_MESSAGE}. ${SEC}"
# For testing.  You could do something cleverer here, if you'd like.
echo ${MESSAGE} | wall
# Shut the machine down.
# Comment this line out if you're just testing, of course. :)
/sbin/shutdown -h now