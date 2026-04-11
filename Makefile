BINARY      = melding
APP         = $(BINARY).app
BUILD_DIR   = .build/release
DIST_DIR    = dist
APP_BUNDLE  = $(DIST_DIR)/$(APP)
INSTALL_APP = /Library/Application\ Support/melding.app
INSTALL_BIN = /usr/local/bin/$(BINARY)

.PHONY: build bundle install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(BINARY)               $(APP_BUNDLE)/Contents/MacOS/
	cp Sources/Melding/Info.plist           $(APP_BUNDLE)/Contents/
	cp Sources/Melding/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Bundle assembled and signed at $(APP_BUNDLE)"

install: bundle
	sudo rm -rf $(INSTALL_APP)
	sudo cp -r $(APP_BUNDLE) $(INSTALL_APP)
	@printf '#!/bin/sh\nexec "%s/Contents/MacOS/$(BINARY)" "$$@"\n' \
		"$(INSTALL_APP)" | sudo tee $(INSTALL_BIN) > /dev/null
	sudo chmod +x $(INSTALL_BIN)
	@echo "Installed to $(INSTALL_BIN) (app bundle at $(INSTALL_APP))"

clean:
	rm -rf $(DIST_DIR) .build
