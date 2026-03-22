APP_NAME = AIQuota
BUILD_DIR = dist
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
SWIFT_FILES = $(wildcard Sources/*.swift)
SWIFTC = swiftc
SDK = $(shell xcrun --show-sdk-path --sdk macosx)
FRAMEWORKS = -framework SwiftUI -framework AppKit

all: $(EXECUTABLE)

$(EXECUTABLE): $(SWIFT_FILES)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Sources/Resources/logo.png $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>$(APP_NAME)</string><key>CFBundleIconFile</key><string>logo.png</string><key>CFBundleIdentifier</key><string>com.aiquota.tracker</string><key>CFBundleName</key><string>$(APP_NAME)</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.0</string><key>LSUIElement</key><true/></dict></plist>' > $(APP_BUNDLE)/Contents/Info.plist
	env TMPDIR=/tmp TMP=/tmp TEMP=/tmp $(SWIFTC) -module-cache-path /tmp/ModuleCache -sdk $(SDK) $(FRAMEWORKS) $(SWIFT_FILES) -o $(EXECUTABLE)
	@touch $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)

run: all
	open $(APP_BUNDLE)
