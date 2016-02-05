#!/bin/bash
set -e

if [ "$1" = 'start' ]; then

  CONTAINERS_FOLDER=/tmp/containers
  NAMED_PIPE=/tmp/pipe

  setConfiguration() {
    KEY=$1
    VALUE=$2
    sed -i "s/{{$KEY}}/$VALUE/g" /filebeat/filebeat.yml
  }

  getRunningContainers() {
    curl --no-buffer -s -XGET --unix-socket /tmp/docker.sock http:/containers/json | python -c "
import json, sys
containers=json.loads(sys.stdin.readline())
for container in containers:
  print(container['Id'])
"
  }

  createContainerFile() {
    touch "$CONTAINERS_FOLDER/$1"
  }

  removeContainerFile() {
    rm "$CONTAINERS_FOLDER/$1"
    echo "Stop processing $1."
  }

  collectContainerLogs() {
    local CONTAINER=$1
    echo "Processing $CONTAINER..."
    createContainerFile $CONTAINER
    echo "Connected to $CONTAINER."
    curl -s --no-buffer -XGET --unix-socket /tmp/docker.sock "http:/containers/$CONTAINER/logs?stderr=1&stdout=1&tail=1&follow=1" > $NAMED_PIPE
    echo "Disconnected from $CONTAINER."
    removeContainerFile $CONTAINER
  }

  if [ -n "${LOGSTASH_HOST+1}" ]; then
    setConfiguration "LOGSTASH_HOST" "$LOGSTASH_HOST"
  else
    echo "LOGSTASH_HOST is needed"
    exit 1
  fi

  if [ -n "${LOGSTASH_PORT+1}" ]; then
    setConfiguration "LOGSTASH_PORT" "$LOGSTASH_PORT"
  else
    echo "LOGSTASH_PORT is needed"
    exit 1
  fi

  if [ -n "${SHIPPER_NAME+1}" ]; then
    setConfiguration "SHIPPER_NAME" "$SHIPPER_NAME"
  else
    setConfiguration "SHIPPER_NAME" "`hostname`"
  fi

  rm -rf "$CONTAINERS_FOLDER"
  rm -rf "$NAMED_PIPE"
  mkdir "$CONTAINERS_FOLDER"
  mkfifo -m a=rw "$NAMED_PIPE"

  echo "Initializing Filebeat..."
  cat $NAMED_PIPE | /filebeat/filebeat -e -v &

  while true; do
    CONTAINERS=`getRunningContainers`
    for CONTAINER in $CONTAINERS; do
      if ! ls $CONTAINERS_FOLDER | grep -q $CONTAINER; then
        collectContainerLogs $CONTAINER &
      fi
    done
    sleep 3
  done

else
  exec "$@"
fi

