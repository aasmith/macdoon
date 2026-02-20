CC = clang
OBJC_FLAGS = -fobjc-arc -std=gnu11 -Wall -Wextra -Wno-unused-parameter
FRAMEWORKS = -framework Cocoa -framework WebKit -framework UniformTypeIdentifiers

APP_NAME = Macdoon
VERSION ?= 0.0.0-dev
BUILD_DIR = build
CMARK_SRC = vendor/cmark-gfm
CMARK_BUILD = $(BUILD_DIR)/cmark-gfm

APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
APP_CONTENTS = $(APP_BUNDLE)/Contents
APP_MACOS = $(APP_CONTENTS)/MacOS
APP_RESOURCES = $(APP_CONTENTS)/Resources
APP_PLUGINS = $(APP_CONTENTS)/PlugIns

CMARK_INCLUDES = -I$(CMARK_BUILD)/src -I$(CMARK_SRC)/src -I$(CMARK_SRC)/extensions
CMARK_LIBS = $(CMARK_BUILD)/extensions/libcmark-gfm-extensions.a \
             $(CMARK_BUILD)/src/libcmark-gfm.a

OBJC_SRCS = src/main.m src/MDAppDelegate.m src/MDWindowController.m src/MDHTMLTemplate.m
C_SRCS = src/MDRenderer.c
OBJS = $(patsubst src/%.m,$(BUILD_DIR)/%.o,$(OBJC_SRCS)) \
       $(patsubst src/%.c,$(BUILD_DIR)/%.o,$(C_SRCS))

# QuickLook extension
QL_APPEX = $(APP_PLUGINS)/MacdoonQL.appex
QL_SRCS = ql/MDQLPreviewProvider.m src/MDHTMLTemplate.m src/MDRenderer.c
QL_FRAMEWORKS = -framework Cocoa -framework QuickLookUI

.PHONY: all clean run install cmark ql dmg sign

all: $(APP_BUNDLE) ql sign

clean:
	rm -rf $(BUILD_DIR)

run: all
	open $(APP_BUNDLE)

install: all
	mkdir -p ~/Applications
	cp -R $(APP_BUNDLE) ~/Applications/
	mkdir -p /usr/local/bin
	ln -sf ~/Applications/$(APP_NAME).app/Contents/MacOS/macdoon /usr/local/bin/macdoon

# --- cmark-gfm ---

cmark: $(CMARK_LIBS)

$(CMARK_LIBS): $(CMARK_SRC)/CMakeLists.txt
	cmake -S $(CMARK_SRC) -B $(CMARK_BUILD) \
		-DCMARK_STATIC=ON \
		-DCMARK_SHARED=OFF \
		-DCMARK_TESTS=OFF \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_FLAGS="-Wno-strict-prototypes" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	cmake --build $(CMARK_BUILD) --config Release

# --- Compile ---

$(BUILD_DIR)/%.o: src/%.m $(CMARK_LIBS) | $(BUILD_DIR)
	$(CC) $(OBJC_FLAGS) $(CMARK_INCLUDES) -c $< -o $@

$(BUILD_DIR)/%.o: src/%.c $(CMARK_LIBS) | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -Wno-unused-parameter $(CMARK_INCLUDES) -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# --- Link ---

$(BUILD_DIR)/macdoon: $(OBJS)
	$(CC) $(OBJC_FLAGS) $(FRAMEWORKS) $(OBJS) $(CMARK_LIBS) -o $@

# --- App Bundle ---

$(APP_BUNDLE): $(BUILD_DIR)/macdoon resources/Info.plist resources/github-markdown.css resources/macdoon.icns
	mkdir -p $(APP_MACOS) $(APP_RESOURCES)
	cp $(BUILD_DIR)/macdoon $(APP_MACOS)/macdoon
	sed 's/$${VERSION}/$(VERSION)/g' resources/Info.plist > $(APP_CONTENTS)/Info.plist
	cp resources/github-markdown.css $(APP_RESOURCES)/github-markdown.css
	cp resources/macdoon.icns $(APP_RESOURCES)/macdoon.icns
	touch $(APP_BUNDLE)

# --- QuickLook Extension ---

ql: $(APP_BUNDLE) $(QL_APPEX)

$(QL_APPEX): $(QL_SRCS) $(CMARK_LIBS) ql/Info.plist ql/Entitlements.plist
	mkdir -p $(QL_APPEX)/Contents/MacOS $(QL_APPEX)/Contents/Resources
	$(CC) $(OBJC_FLAGS) $(QL_FRAMEWORKS) \
		$(CMARK_INCLUDES) -Isrc \
		-e _NSExtensionMain \
		-fapplication-extension \
		$(QL_SRCS) $(CMARK_LIBS) \
		-o $(QL_APPEX)/Contents/MacOS/MacdoonQL
	sed 's/$${VERSION}/$(VERSION)/g' ql/Info.plist > $(QL_APPEX)/Contents/Info.plist
	cp resources/github-markdown.css $(QL_APPEX)/Contents/Resources/github-markdown.css

# --- Code Signing (inside-out: extension first, then app) ---

sign: $(QL_APPEX)
	codesign --force --sign - \
		--entitlements ql/Entitlements.plist \
		$(QL_APPEX)
	codesign --force --sign - \
		$(APP_BUNDLE)

# --- DMG ---

dmg: all
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
