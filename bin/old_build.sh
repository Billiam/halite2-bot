#!/usr/bin/env bash
die () {
    echo >&2 "$@"
    exit 1
}

[ "$#" -eq 1 ] || die "Git hash argument not required.\nUsage: bin/old_build.sh <HEAD|git_hash>"

git archive --format=zip "$1" -o old_bot.zip
rm -r tmp/last_bot/*
unzip old_bot.zip -d tmp/last_bot
