#!/usr/bin/env sh

luajit lua.lua lua.lua lua.js

node lua.js "$@"
