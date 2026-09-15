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
	install -Dm755 livediag "$(DESTDIR)$(PREFIX)/bin/livediag"
	install -Dm644 lib/common.sh "$(DESTDIR)$(PREFIX)/share/livediag/lib/common.sh"
	install -Dm644 lib/report.sh "$(DESTDIR)$(PREFIX)/share/livediag/lib/report.sh"
	install -Dm644 tests/tests.list "$(DESTDIR)$(PREFIX)/share/livediag/tests/tests.list"
	@for f in tests/*.sh; do \
		case "$$f" in */template.sh) continue ;; esac; \
		install -Dm644 "$$f" "$(DESTDIR)$(PREFIX)/share/livediag/tests/$$(basename "$$f")"; \
	done
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/livediag/README.md"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/livediag/LICENSE"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/livediag"
	rm -rf "$(DESTDIR)$(PREFIX)/share/livediag"
	rm -rf "$(DESTDIR)$(PREFIX)/share/doc/livediag"
	rm -rf "$(DESTDIR)$(PREFIX)/share/licenses/livediag"
