#!/usr/bin/env bash

set -e
USER_ID=2950
VERSION=`curl -s "http://api.halite.io/v1/api/user/$USER_ID/bot/0" | grep -Pom 1 '(?<="version_number": )\d+'`
git tag "v$VERSION"
echo "Tagged as $VERSION"

