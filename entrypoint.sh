#!/bin/bash

function log() {
  echo "[$(date --utc -Ins)]   $1"
}

function shutdown() {
  if ((SHUTTING == 0)); then
    SHUTTING=1
    log "Shutdown triggered"
    nginx -s quit || log "Failed to shutdown NGINX gracefully"
    kill -s SIGQUIT "$PID_PHP" || log "Failed to shutdown PHP-FPM gracefully"
    if [ "$1" == "sigterm" ]; then EXIT_STATUS=143; fi
  fi
}

trap "shutdown sigterm" SIGTERM
log "Starting PHP-FPM"
php-fpm &
PID_PHP=$!

CHECK_I=0
until FCGI_STATUS_PATH=/p00l-status php-fpm-healthcheck; do
  sleep 0.1
  ((CHECK_I++))
  if ((CHECK_I > 99)); then
    log "PHP-FPM failed to start"
    exit
  fi
done

log "Starting NGINX"
/20-envsubst-on-templates.sh
nginx &
log "$(nginx -V 2>&1 | head -n 1), PID $!"

wait -n
EXIT_STATUS=$?
shutdown auto
wait
log "Shutdown completed"
exit $EXIT_STATUS
