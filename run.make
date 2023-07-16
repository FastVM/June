
ECHO = printf ''
LUA = lua
IN = lua.lua
ARG = 

run: fmt.js .dummy
	@${ECHO} "node fmt.js ${ARG}"
	@node fmt.js ${ARG}

fmt.js: out.js
	@${ECHO} "prettier out.js > fmt.js"
	@prettier out.js > fmt.js

out.js: config.make lua.lua ${IN}
	@${ECHO} "lua.lua ${IN} ${@}"
	@${LUA} lua.lua ${IN} ${@}

.dummy:

.PHONY: .dummy