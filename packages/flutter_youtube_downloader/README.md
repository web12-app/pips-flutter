# flutter_youtube_downloader (vendored)

Vendored fork of the pub.dev package (0.0.5) with a working 2026 extraction engine.

- Dart API unchanged: `FlutterYoutubeDownloader.extractYoutubeLink(url, itag)` / `downloadVideo(...)`
- Android only; the upstream `at.huber.youtubeExtractor` engine (retired `get_video_info` endpoint) was replaced with **NewPipe Extractor v0.26.5** (jitpack) + a plain HttpURLConnection downloader.
- build.gradle matches the modern template used by `video_thumbnail` (namespace, flutter.compileSdkVersion, no jcenter).
