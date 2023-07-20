#!/usr/bin/env sh

test -f lua.js || luajit lua.lua lua.lua lua.js

node lua.js "$@"
