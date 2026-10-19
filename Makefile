PREFIX ?= $(HOME)/.local
BIN := $(PREFIX)/bin

.PHONY: build install uninstall

build:
	swift build -c release

# Each rebuild changes the binary's hash, so the keychain asks once per key
# ("key wants to use…") after an upgrade: enter the login password, Always Allow.
install: build
	install -d $(BIN)
	install -m 755 .build/release/key $(BIN)/key
	ln -sf key $(BIN)/getkey

uninstall:
	rm -f $(BIN)/key $(BIN)/getkey
