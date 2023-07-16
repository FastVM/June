
TESTS := $(shell find bench -name '*.lua')

tests: .dummy
	@echo > bench/all.log
	@for test in ${TESTS}; do ${MAKE} -B -f run.make IN=$$test > $$test.res 2>> bench/all.log || true; done

clean: .dummy
	@find bench -type f -not -name '*.lua' -exec rm {} ';'

.dummy:

.PHONY: .dummy
