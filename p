#!/usr/bin/env bash

set -e

LOG=${LOGFILE-$HOME/.p.log}
BREAK_LOG=${LOGFILE-$HOME/.p-break.log}

DATE_FORMAT="%Y-%m-%d %T %z"

# 1500 = 25 Mins of work
POMODORO_LENGTH_IN_SECONDS=15

# 300 = 5 Mins Short Break
POMODORO_BREAK_IN_SECONDS=300

# 1800 = 30 Mins of Long Break
POMODORO_LONG_BREAK_IN_SECONDS=1800

# 3000 = 50 Mins
POMODORO_AWAY_IN_SECONDS=3000

PREFIX=""
TMPFILE=/tmp/p-${RANDOM}
INTERNAL_INTERRUPTION_MARKER="'"
EXTERNAL_INTERRUPTION_MARKER="-"
DATE=date

function deleteLastLine
{
  if [ -s "$LOG" ]; then
    sed '$ d' "$LOG" > $TMPFILE
    mv $TMPFILE "$LOG"
  fi
}

function convertTimeFormat
{
  TIME_STRING="$1"
  OUTPUT_FORMAT="$2"
  $DATE --version 2>&1 | grep "GNU coreutils" > /dev/null
  if [ "$?" == "0" ]; then
    $DATE -d "$TIME_STRING" "$OUTPUT_FORMAT"
  else
    $DATE -j -f "$DATE_FORMAT" "$TIME_STRING" "$OUTPUT_FORMAT"
  fi
}

function nowFormattted
{
  OUTPUT_FORMAT="$1"
  $DATE --version 2>&1 | grep "GNU coreutils" > /dev/null
  if [ "$?" == "0" ]; then
    $DATE "+$OUTPUT_FORMAT"
  else
    $DATE -f "$OUTPUT_FORMAT"
  fi
}

function checkLastPomodoro
{
  if [ -s "$LOG" ]; then
    RECENT=$(tail -1 ${LOG})
    TIME=$(echo $RECENT | cut -d ',' -f 1)
    INTERRUPTIONS=$(echo $RECENT | cut -d ',' -f 2)
    THING=$(echo $RECENT | cut -d ',' -f 3-)
    TIMESTAMP_RECENT=$(convertTimeFormat "$TIME" "+%s")
    TIMESTAMP_NOW=$($DATE "+%s")
    SECONDS_ELAPSED=$((TIMESTAMP_NOW - TIMESTAMP_RECENT))
    if (( $SECONDS_ELAPSED >= $POMODORO_LENGTH_IN_SECONDS )); then
      POMODORO_FINISHED=1
      breakType
      startBreak
      BREAK_RECENT=$(tail -1 ${BREAK_LOG})
      BREAK_TIME=$(echo $BREAK_RECENT | cut -d ',' -f 1)
      BREAK_TIMESTAMP_RECENT=$(convertTimeFormat "$BREAK_TIME" "+%s")
      BREAK_TIMESTAMP_NOW=$($DATE "+%s")
      BREAK_SECONDS_ELAPSED=$((BREAK_TIMESTAMP_NOW - BREAK_TIMESTAMP_RECENT))
    else
      POMODORO_FINISHED=0
    fi
  else
    NO_RECORDS=1
  fi
}

function cancelRunningPomodoro
{
  checkLastPomodoro
  if [ "$POMODORO_FINISHED" == "0" ]; then
    if [ -z $NO_RECORDS ]; then
      deleteLastLine
      echo $1
    fi
  fi
}

function interrupt
{
  type=$1
  checkLastPomodoro
  if [ "$POMODORO_FINISHED" == "0" ]; then
    deleteLastLine
    echo $TIME,$INTERRUPTIONS$type,$THING >> "$LOG"
    echo "Interrupt recorded"
  else
    echo "No pomodoro to interrupt"
    exit 1
  fi
}

function startBreak
{
  type=$1
  if [ "$POMODORO_FINISHED" == "1" ]; then
    echo $TIME,$type,$THING >> "$BREAK_LOG"
  fi
}

function optionalDescription
{
  OPTIONAL_THING="$1"
  if [ ! -z "${OPTIONAL_THING}" ]; then
    ON_THING="on \"${OPTIONAL_THING}\""
  fi
}

function displayLine
{
  MIN=$(($1 / 60))
  SEC=$(($1 % 60))
  optionalDescription "$2"
  printf "$3" $MIN $SEC "$ON_THING"
}

function startPomodoro
{
  THING=$1
  NOW=$($DATE +"$DATE_FORMAT")
  echo "$NOW,,$THING" >> "$LOG"
  optionalDescription "$THING"
  echo "Pomodoro started $ON_THING"
}

function waitForCompletion
{
  TICK_COMMAND="$1"
  COMPLETED_COMMAND="$2"
  checkLastPomodoro
  if [ "$POMODORO_FINISHED" == "0" ]; then
    while [ "$POMODORO_FINISHED" == "0" ]; do
      REMAINING=$((POMODORO_LENGTH_IN_SECONDS - SECONDS_ELAPSED))
      displayLine $REMAINING "$THING" "\r$PREFIX %02d:%02d %s"
      sleep 1
      checkLastPomodoro
      if [ ! -z "$TICK_COMMAND" ]; then
        ( $TICK_COMMAND ) &
      fi
    done
    if [ ! -z "$COMPLETED_COMMAND" ]; then
      ( $COMPLETED_COMMAND ) &
    fi
  fi
}

function showStatus
{
  checkLastPomodoro
  if [ -z $NO_RECORDS ]; then
    if [ "$POMODORO_FINISHED" == "1" ]; then
      BREAK=$((SECONDS_ELAPSED - POMODORO_LENGTH_IN_SECONDS))
      if (( $BREAK < $POMODORO_BREAK_IN_SECONDS )); then
        displayLine $BREAK "$THING" "$PREFIX Completed %02d:%02d ago %s"
      else
        LAST=$(convertTimeFormat "$TIME" "+%a, %d %b %Y %T")
        printf "Most recent pomodoro: $LAST"
      fi
    else
      REMAINING=$((POMODORO_LENGTH_IN_SECONDS - SECONDS_ELAPSED))
      displayLine $REMAINING "$THING" "$PREFIX %02d:%02d %s"
    fi
  fi
}

function shortShowStatus
{
  checkLastPomodoro
  statusIcon
  if [ -z $NO_RECORDS ]; then
    if [ "$POMODORO_FINISHED" == "1" ]; then
      if (( $BREAK_SECONDS_ELAPSED < $POMODORO_BREAK_IN_SECONDS )); then
        if [ "$BREAK" == "SHORT" ]; then
          REMAINING=$((POMODORO_BREAK_IN_SECONDS - BREAK_SECONDS_ELAPSED))
        else
          REMAINING=$((POMODORO_LONG_BREAK_IN_SECONDS - BREAK_SECONDS_ELAPSED))
        fi
      else
        if (( $BREAK_SECONDS_ELAPSED < $POMODORO_LONG_BREAK_IN_SECONDS )); then
          if [ "$BREAK" == "SHORT" ]; then
            REMAINING=$((0))
          else
            REMAINING=$((POMODORO_LONG_BREAK_IN_SECONDS - BREAK_SECONDS_ELAPSED))
          fi
        else
          if (( $BREAK_SECONDS_ELAPSED < $POMODORO_AWAY_IN_SECONDS )); then
            REMAINING=$((0))
          else
            REMAINING=$((0))
          fi
        fi
      fi

      TIME=$(printf '%dm:%ds' $(($REMAINING%3600/60)) $(($REMAINING%60)))
      echo -e "$ICON $TIME"
    else
      REMAINING=$((POMODORO_LENGTH_IN_SECONDS - SECONDS_ELAPSED))
      TIME=$(printf '%dm:%ds' $(($REMAINING%3600/60)) $(($REMAINING%60)))
      echo -e "$ICON $TIME"
    fi
  fi
}

function statusIcon
{
  if [ -z $NO_RECORDS ]; then
    if [ "$POMODORO_FINISHED" == "1" ]; then
      if (( $BREAK_SECONDS_ELAPSED < $POMODORO_BREAK_IN_SECONDS )); then
        if [ "$BREAK" == "SHORT" ]; then
          ICON=""
        else
          ICON=""
        fi
      else
        if (( $BREAK_SECONDS_ELAPSED < $POMODORO_LONG_BREAK_IN_SECONDS )); then
          if [ "$BREAK" == "SHORT" ]; then
            ICON=""
          else
            ICON=""
          fi
        else
          if (( $BREAK_SECONDS_ELAPSED < $POMODORO_AWAY_IN_SECONDS )); then
            ICON=""
          else
            ICON=""
          fi
        fi
      fi
    else
# if external interrupted then    else internal interrupt 
      ICON=""
    fi
  fi
}

function countCompletedPomodoros
{
  TODAY=$(nowFormattted $DATE_FORMAT)
  if [ -z $NO_RECORDS ]; then
     if [ "$POMODORO_FINISHED" == "1" ]; then
       COMPLETED_POMODOROS=$(sed -e "/$TODAY/!d" ${LOG} | wc -l - | cut -s -f 1 -d " " -)
     else
       COMPLETED_POMODOROS=$(tail -1 ${LOG} | sed -e "/$TODAY/!d" - | wc -l - | cut -s -f 1 -d " " -)
     fi
  fi
}

function breakType
{
  countCompletedPomodoros
  ISREADY=$(($COMPLETED_POMODOROS % 4))
  if [ "$ISREADY" == "0" ]; then
    BREAK="LONG"
  else
    BREAK="SHORT"
  fi
}

function interruptType {
  echo $INTERRUPTIONS
}

case "$1" in
  start | s)
    cancelRunningPomodoro "Last Pomodoro cancelled"
    startPomodoro "${*:2}"
    ;;
  cancel | c)
    cancelRunningPomodoro "Cancelled. The next Pomodoro will go better!"
    ;;
  internal | i)
    interrupt $INTERNAL_INTERRUPTION_MARKER
    ;;
  external | e)
    interrupt $EXTERNAL_INTERRUPTION_MARKER
    ;;
  wait | w)
    waitForCompletion "${*:2}" ""
    ;;
  short-status | ss)
    shortShowStatus
    ;;
  loop)
    while true; do
      printf "\r                                                               "
      waitForCompletion "$2" "$3"
      printf "\r"
      showStatus
      sleep 1
    done
    ;;
  log | l)
    cat "$LOG"
    ;;
  help | h | -h)
    echo "usage: p [command]"
    echo
    echo "Available commands:"
    echo "   status (default)         Shows information about the current pomodoro"
    echo "   start [description]      Starts a new pomodoro, cancelling any in progress"
    echo "   cancel                   Cancels any pomodoro in progress"
    echo "   internal                 Records an internal interruption on current pomodoro"
    echo "   external                 Records an external interruption on current pomodoro"
    echo "   wait [command]           Prints ticking counter and blocks until pomodoro completion."
    echo "                            Optionally runs 'command' every second"
    echo "   loop <tick> <end>        Prints ticker and runs 'tick' every second and 'end' at"
    echo "                            completion. Blocks until next pomodoro starts."
    echo "   log                      Shows pomodoro log output in CSV format"
    echo "   help                     Prints this help text"
    echo
    echo "Most commands may be shortened to their first letter. For more information"
    echo "see http://github.com/chrismdp/p."
    ;;
  status | *)
    showStatus
    printf "\n"
    ;;
esac
