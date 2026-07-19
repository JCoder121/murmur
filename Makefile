APP = WisprClone
BIN = .build/release/$(APP)
BUNDLE = dist/$(APP).app

.PHONY: build bundle run test clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force -s - --identifier com.jeffrey.wisprclone $(BUNDLE)

run: bundle
	open $(BUNDLE)

test:
	swift test

clean:
	rm -rf .build dist
