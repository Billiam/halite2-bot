#!/usr/bin/env bash

mv bot.zip previous_bot.zip
git archive --format=zip HEAD -o bot.zip
rm -r tmp/last_bot/*
unzip bot.zip -d tmp/last_bot
