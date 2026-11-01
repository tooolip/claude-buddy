#!/bin/zsh
# Prints Claude Buddy's memory use: RSS, and the "physical footprint" Activity Monitor shows.
pid=$(pgrep -x ClaudeBuddy) || { echo "Claude Buddy isn't running"; exit 1; }
rss_kb=$(ps -o rss= -p $pid | tr -d ' ')
cpu=$(ps -o %cpu= -p $pid | tr -d ' ')
fp=$(footprint $pid 2>/dev/null | awk '/phys_footprint:/ {print $2, $3; exit}')
echo "pid $pid  RSS $((rss_kb / 1024)) MB  footprint ${fp:-?}  CPU ${cpu}%"
