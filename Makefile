APP = WisprClone
BIN = .build/release/$(APP)
BUNDLE = dist/$(APP).app

# "WisprClone Dev" is a self-signed cert in the login keychain; a stable identity
# keeps TCC grants (Accessibility) valid across rebuilds, unlike ad-hoc signing.
# Falls back to ad-hoc if the cert is missing (fresh machine).
SIGN_ID = $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "WisprClone Dev" && echo "WisprClone Dev" || echo "-")

.PHONY: build bundle run test clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force -s "$(SIGN_ID)" --identifier com.jeffrey.wisprclone $(BUNDLE)

run: bundle
	open $(BUNDLE)

test:
	swift test

clean:
	rm -rf .build dist
