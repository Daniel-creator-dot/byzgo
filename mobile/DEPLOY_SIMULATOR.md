# Deploy BytzGo to iPhone Simulator (Mac)

## 1. Get latest code

```bash
cd ~/Downloads/byzgo-main   # your clone path
git pull origin main
```

## 2. Build & run (one step)

In Finder, open the `mobile` folder and **double-click**:

**`BUILD_IOS_SIMULATOR.command`**

(Right-click → **Open** if macOS blocks it.)

## 3. Or Terminal

```bash
cd mobile
./BUILD_IOS_SIMULATOR.command
```

## Requirements (once)

```bash
brew install --cask flutter
brew install cocoapods
```

## Version

Check **Settings → About** in the app for **1.0.14** (build 16) or newer — includes live admin pricing updates.

## API

Uses `https://www.bytzgo.net` unless you have `dart_defines.json` pointing to local backend.
