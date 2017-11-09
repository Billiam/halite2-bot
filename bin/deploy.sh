#!/usr/bin/env bash
set -e

USER_ID="2950"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

hlt_client bot -b bot.zip

VERSION=`curl -s "http://api.halite.io/v1/api/user/$USER_ID/bot/0" | grep -Pom 1 '(?<="version_number": )\d+'`
git tag -f "v$VERSION"
echo "Tagged as $VERSION"
