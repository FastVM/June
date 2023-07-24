SRCS = $(shell find test/lua5.4.6 -name '*.lua')
JS = $(SRCS:%.lua=%.js)

$(info $(RESS))

default: test

test: $(JS)

$(JS): $(@:%.js=%.lua)
	luajit lua.lua $(@:%.js=%.lua) $(@)

clean:
	rm $(JS)

.PHONY: test default clean
