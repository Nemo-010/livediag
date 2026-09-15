PREFIX ?= /usr
DESTDIR ?=
VERSION := 0.1.0

.PHONY: all check install uninstall

all: check

check:
	@for f in livediag lib/*.sh tests/*.sh; do \
		sh -n "$$f" || exit 1; \
	done
	@printf 'livediag %s: syntax ok\n' "$(VERSION)"

install:
	mkdir -p "$(DESTDIR)$(PREFIX)/bin" \
		"$(DESTDIR)$(PREFIX)/share/livediag/lib" \
		"$(DESTDIR)$(PREFIX)/share/livediag/tests" \
		"$(DESTDIR)$(PREFIX)/share/doc/livediag" \
		"$(DESTDIR)$(PREFIX)/share/licenses/livediag"
	cp livediag "$(DESTDIR)$(PREFIX)/bin/livediag"
	chmod 755 "$(DESTDIR)$(PREFIX)/bin/livediag"
	cp lib/common.sh lib/report.sh "$(DESTDIR)$(PREFIX)/share/livediag/lib/"
	chmod 644 "$(DESTDIR)$(PREFIX)/share/livediag/lib/"*.sh
	cp lib/stages.py "$(DESTDIR)$(PREFIX)/share/livediag/lib/stages.py"
	chmod 644 "$(DESTDIR)$(PREFIX)/share/livediag/lib/stages.py"
	cp tests/tests.list "$(DESTDIR)$(PREFIX)/share/livediag/tests/tests.list"
	@for f in tests/*.sh; do \
		case "$$f" in */template.sh) continue ;; esac; \
		cp "$$f" "$(DESTDIR)$(PREFIX)/share/livediag/tests/$$(basename "$$f")"; \
	done
	chmod 644 "$(DESTDIR)$(PREFIX)/share/livediag/tests/"*.sh \
		"$(DESTDIR)$(PREFIX)/share/livediag/tests/tests.list"
	cp README.md "$(DESTDIR)$(PREFIX)/share/doc/livediag/README.md"
	cp LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/livediag/LICENSE"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/livediag"
	rm -rf "$(DESTDIR)$(PREFIX)/share/livediag"
	rm -rf "$(DESTDIR)$(PREFIX)/share/doc/livediag"
	rm -rf "$(DESTDIR)$(PREFIX)/share/licenses/livediag"
