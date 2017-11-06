#!/usr/bin/env bash

hlt_client gym -r "ruby MyBot.rb" -r "ruby tmp/last_bot/MyBot.rb" --binary "$PWD/halite" "$@"
