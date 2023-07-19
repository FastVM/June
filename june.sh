#!/usr/bin/env sh

test -f lua.js || luajit lua.lua lua.lua lua.js

~/.bun/bin/bun lua.js "$@"
