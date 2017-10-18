#!/bin/sh
set -e
user="$1"
psql -c "create database talkrec template template0 encoding 'UTF8' lc_collate 'ru_RU.UTF8' lc_ctype 'ru_RU.UTF8'"
psql -c "grant all on database talkrec to \"$user\""

