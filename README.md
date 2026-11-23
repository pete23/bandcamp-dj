bandcamp-sync
=========================

Downloads new purchases from Bandcamp and imports them into Apple Music, from the
command line or a Mac app. Both are thin front ends over the same Swift libraries,
so they do exactly the same thing.

The plan, all done:

1. A CLI tool that can list recent purchases from Bandcamp.
2. then let it enumerate the content of Music
3. then let it find purchases not in Music
4. and load them to Music
5. put a GUI on it for normal people

## Getting started

You need macOS 14 or later and Swift 6 (Xcode 16, or its command line tools:
`xcode-select --install`).

```
git clone https://github.com/pete23/bandcamp-dj.git
cd bandcamp-dj
Scripts/build-app.sh /Applications    # then open "Bandcamp Sync" from Applications
```

The first time:

1. **Bandcamp cookie.** It asks for your browser's Bandcamp `identity` cookie and
   tells you where to find it. It's saved to `~/.config/bandcamp-sync/identity`
   (readable only by you), where the app and the command line both find it. When
   it expires, you'll be asked again.
2. **Music library access.** macOS asks whether it may read your Music library.
3. **Controlling Music.** The first sync asks whether it may control Music, to add
   the downloads. Music opens if it isn't running.

To get the command line on your `PATH`:

```
swift build -c release --product bandcamp-sync
cp .build/release/bandcamp-sync /usr/local/bin/    # or anywhere on your PATH
bandcamp-sync missing
```

### Troubleshooting

- **"Couldn't read the Music library" or "Not allowed to control Music":** allow the
  app (or, for the command line, your terminal) under System Settings → Privacy &
  Security → Media & Apple Music and → Automation. The app is signed ad hoc, so macOS
  may ask again after you rebuild it.
- **A purchase you already have shows as not in Music:** the library match goes by
  title and artist (and Bandcamp links in track comments). `bandcamp-sync missing
  --matched` shows what everything matched. Nothing is imported twice: imported
  folders are marked with a `.bandcamp-imported.json` file.
- **Something went wrong mid-download:** just sync again. Finished downloads are
  skipped, and unfinished ones restart.

## Using it

### App

```
Scripts/build-app.sh                 # builds .build/Bandcamp Sync.app
Scripts/build-app.sh /Applications   # or puts it straight in Applications
swift run BandcampSyncApp            # or runs it unbundled, for development
```

The window lists your recent purchases that aren't in Music and how far each has got.
**Sync** downloads the missing ones and adds them to Music. Settings has the format,
download folder, how many purchases to check and how many to download at once.

### Command line

```
swift run bandcamp-sync list               # recent purchases
swift run bandcamp-sync music              # albums in your Music library
swift run bandcamp-sync missing            # purchases not in Music, and how far each has got
swift run bandcamp-sync download --import  # download them and add them to Music
swift run bandcamp-sync import             # add earlier downloads to Music
```

| App | Command line |
|---|---|
| The window's list (Not in Music / All Recent) | `missing` / `missing --matched` |
| Sync | `download --import` |
| Settings: format, folder, purchases to check, downloads at once | `--format`, `--to`, `--limit`, `--parallel` |

The defaults are the same in both: MP3 320 into `~/Downloads/bandcamp-sync`, checking
the last 50 purchases, 6 downloads at a time.

Unless Music's "Copy files to Music Media folder" setting is on, Music plays imported
files from the download folder, so keep it.

## How it fits together

- `BandcampKit`: Bandcamp's (unofficial) fan API, the identity cookie, downloads.
- `MusicLibraryKit`: reads the library (iTunesLibrary) and adds files to it (by
  scripting Music.app; there's no framework API for that).
- `SyncKit`: matches purchases to the library and runs a sync: `Sync` says where each
  purchase has got to, `Downloader` and `Importer` do the two steps.
- `bandcamp-sync` (CLI) and `BandcampSyncApp` (SwiftUI) only ask for the cookie and
  show progress, each in its own way.
