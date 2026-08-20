APP := Shuntbar
BUNDLE := $(APP).app
BINARY := .build/release/$(APP)

.PHONY: build test app run clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Info.plist $(BUNDLE)/Contents/
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/
	codesign --force --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: app
	open $(BUNDLE)

clean:
	swift package clean
	rm -rf $(BUNDLE)
