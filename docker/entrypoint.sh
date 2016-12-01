#!/bin/bash
set -e

if [ "$1" = 'newque' ]; then
    cd /newque
fi

exec "$@"
