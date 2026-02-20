# Macdoon

A lightweight, native macOS markdown viewer with GitHub-flavored rendering. No editing, no bloat — just fast, styled previews.

- **GFM support** — tables, task lists, strikethrough, autolinks via [cmark-gfm](https://github.com/github/cmark-gfm)
- **GitHub CSS** — light and dark mode, automatic
- **Live reload** — re-renders on file save, preserves scroll position
- **QuickLook** — spacebar preview in Finder
- **CLI** — `macdoon README.md` or `cat file.md | macdoon`
- **Native** — Objective-C, AppKit, WKWebView. No Electron.

## Install

Download the latest DMG from [Releases](../../releases), open it, and drag **Macdoon.app** to `/Applications`.

For the command line tool, open Macdoon and go to **Macdoon > Install Command Line Tool…**

## Usage

**GUI:**
- Double-click any `.md` file (after setting Macdoon as the default viewer)
- Right-click a `.md` file → Open With → Macdoon
- Drag files onto the app window or dock icon
- File → Open (⌘O)

**CLI:**
```
macdoon README.md
macdoon ~/notes/*.md
cat CHANGELOG.md | macdoon
```

**QuickLook:**

Select a `.md` file in Finder and press Space.

## Build from source

Requires Xcode Command Line Tools and [CMake](https://cmake.org):

```
brew install cmake
```

Then:

```
git clone --recursive https://github.com/aasmith/macdoon.git
cd macdoon
make
```

This builds `build/Macdoon.app` with the QuickLook extension embedded.

Other targets:

```
make run          # build and launch
make install      # copy to ~/Applications + symlink CLI to /usr/local/bin
make dmg          # package as .dmg
make clean        # remove build/
```

Pass `VERSION=x.y.z` to set the version in Info.plist:

```
make VERSION=1.0.0 dmg
```

## How it works

Markdown is parsed by [cmark-gfm](https://github.com/github/cmark-gfm) (GitHub's fork of cmark, with extensions for tables, task lists, strikethrough, autolinks, and tag filtering) into HTML, then rendered in a WKWebView with [github-markdown-css](https://github.com/sindresorhus/github-markdown-css).

Dark mode works automatically — the CSS uses `prefers-color-scheme` media queries, and WKWebView passes through the system appearance.

Live reload uses `dispatch_source` with `DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME` to handle both direct writes and atomic-save editors (vim, VS Code, etc.) that replace the file via rename.

The QuickLook extension can't use WKWebView (WebKit subprocesses get killed in the app extension sandbox), so it walks the cmark-gfm AST directly and builds an `NSAttributedString` rendered in an `NSTextView`.

## License

MIT
