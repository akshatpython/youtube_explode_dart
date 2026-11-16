# Wave Music — offline-capable music streaming & downloader (Flutter)

A complete Flutter app that streams and downloads music **directly on-device**
with `youtube_explode_dart` — no backend server. Background/lock-screen
playback is provided by `just_audio` + `audio_service`; downloads are stored
as `.m4a` files with metadata in `shared_preferences` for instant offline use.

## 1. Verify these packages in `pubspec.yaml`

| Package | Constraint used | Purpose |
|---|---|---|
| `youtube_explode_dart` | `path: ../../` (this repo) / `^3.1.0` on pub.dev | Search + stream resolution, on-device |
| `just_audio` | `^0.10.5` | Audio playback engine |
| `audio_service` | `^0.18.18` | Media notification, lock screen, headset controls |
| `audio_session` | `^0.1.21` | Audio focus / interruption handling |
| `path_provider` | `^2.1.5` | Application documents directory for downloads |
| `shared_preferences` | `^2.5.3` | Persisted download metadata (JSON) |

Requires Flutter **≥ 3.27** / Dart **≥ 3.6**. Run:

```bash
flutter pub get
flutter analyze
flutter test
```

## 2. Android setup (already applied in this folder)

`android/app/src/main/AndroidManifest.xml` in this folder is a drop-in
replacement for a standard Flutter app's manifest. It declares:

- `INTERNET`, `ACCESS_NETWORK_STATE` — streaming/downloads
- `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` — background playback (the last one is mandatory on Android 14+)
- `POST_NOTIFICATIONS` — media notification on Android 13+
- `com.ryanheise.audioservice.AudioService` (`foregroundServiceType="mediaPlayback"`, `android.media.browse.MediaBrowserService` intent)
- `com.ryanheise.audioservice.MediaButtonReceiver` (`MEDIA_BUTTON` intent)

`MainActivity` must extend `AudioServiceActivity` (see
`android/app/src/main/kotlin/com/example/music_streaming_app/MainActivity.kt`):

```kotlin
package com.example.music_streaming_app

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
```

In `android/app/build.gradle(.kts)`, keep your Flutter-generated values;
the plugins require at least:

```kotlin
android {
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        applicationId = "com.example.music_streaming_app"
        minSdk = flutter.minSdkVersion   // 23+ recommended
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
    }
}
```

### Materialising the platform folders

This repository ships the app's `lib/`, `pubspec.yaml` and Android overrides
(the library repo itself has no Flutter toolchain). To run it:

1. Create a scratch app: `flutter create --project-name music_streaming_app /tmp/wave_music`
2. Copy this folder's `lib/`, `test/` and `pubspec.yaml` over the scratch app
   (adjust the `youtube_explode_dart` path dependency if you move it).
3. Replace the scratch app's `android/app/src/main/AndroidManifest.xml` with
   the one from this folder, and make `MainActivity` extend
   `AudioServiceActivity` as above.
4. `flutter pub get && flutter run` (or `flutter build apk --release`).

> Note on streaming reliability: some videos require signature/`n`-parameter
> solving. This checkout of `youtube_explode_dart` supports JS challenge
> solvers — see the package's `lib/solvers.dart` if a stream fails to load
> for a specific video, and pass a solver to `YoutubeExplode(jsSolver: ...)`.

## 3. Project structure

```
lib/
├── main.dart                     # App entry: AudioService.init, DI, theme
├── models/
│   └── track.dart                # Track model (search/queue/offline, JSON, MediaItem)
├── theme/
│   └── app_theme.dart            # Spotify-inspired dark Material 3 theme
├── services/
│   ├── yt_service.dart           # YoutubeExplode wrapper: search, 30-min URL cache
│   ├── audio_handler.dart        # just_audio + audio_service background handler
│   └── download_service.dart     # .m4a downloads, progress, SharedPreferences index
├── screens/
│   ├── home_screen.dart          # Discover/Search, Downloads, Queue tabs + shell
│   └── player_screen.dart        # Full-screen Now Playing
└── widgets/
    ├── mini_player.dart          # Persistent mini-player (marquee title, progress)
    └── song_tile.dart            # Song rows, artwork, download button states
```

## 4. How it works

- **Search**: debounced (600 ms) via `yt.search.search(query)`; live streams
  and duration-less results are filtered out. Quick-search chips seed queries.
- **Streaming**: `yt.videos.streamsClient.getManifest(id)` →
  `manifest.audioOnly.withHighestBitrate().url`. Resolved URLs are cached
  in memory for 30 minutes (`YtService.cacheTtl`).
- **Playback**: a `ConcatenatingAudioSource` queue gives true Shuffle and
  Repeat Off/All/One from `just_audio`; `MusicAudioHandler` mirrors state
  into `audio_service` for the notification/lock screen. Downloaded tracks
  in a queue automatically play from their local file.
- **Downloads**: bytes are streamed to `<app-documents>/music_downloads/<videoId>.m4a.part`,
  then renamed to `.m4a` on completion. Progress (0.0–1.0) is exposed via
  `DownloadService.progress` (`ValueNotifier<Map<String, double>>`); metadata
  is persisted as JSON in `shared_preferences` under
  `wave_music.downloaded_tracks.v1`, so the offline library loads instantly
  with no network. Downloads can be cancelled (partial files are removed)
  and deleted from the Downloads tab.
- **Offline**: with no connection, search shows a friendly error while the
  Downloads tab and any queued local files keep playing.

## 5. Behaviour notes

- Tapping a search result queues the whole result list (Next/Previous walk
  it); tapping a download queues the whole offline library.
- Previous restarts the current song when pressed more than 3 s in.
- If a stream URL expires mid-queue, its cache entry is invalidated so the
  next play resolves a fresh URL.
