# macOS ties the Accessibility grant to the signing identity, so an ad-hoc
# signature would lose it on every rebuild. Any stable identity works.
IDENTITY ?= Tenure Local
APP := build/Tessera.app
INSTALL_DIR := $(HOME)/Applications
# `tessera status | cycle | push` from a shell.
BIN_DIR ?= $(HOME)/bin

.PHONY: app install run check test clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Tessera $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	codesign --force --sign "$(IDENTITY)" $(APP)

install: app
	-pkill -x Tessera
	rm -rf $(INSTALL_DIR)/Tessera.app
	cp -R $(APP) $(INSTALL_DIR)/
	mkdir -p $(BIN_DIR)
	ln -sf $(INSTALL_DIR)/Tessera.app/Contents/MacOS/Tessera $(BIN_DIR)/tessera
	open $(INSTALL_DIR)/Tessera.app

check:
	swift run -q Tessera --check

# The Command Line Tools toolchain intermittently fails to find the Swift
# Testing macro plugin; loading it in-process avoids that.
TESTING_MACROS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib

test:
	swift test $(if $(wildcard $(TESTING_MACROS)),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_MACROS))

clean:
	rm -rf .build build
