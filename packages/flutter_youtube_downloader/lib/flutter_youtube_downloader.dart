import 'dart:async';

import 'package:flutter/services.dart';

/// Dart API (kept identical to the upstream flutter_youtube_downloader 0.0.5
/// package so the documented usage compiles unchanged):
///
/// ```dart
/// final youTubeLink = "https://www.youtube.com/watch?v=...";
/// String? url = await FlutterYoutubeDownloader.extractYoutubeLink(youTubeLink, 18);
/// ```
///
/// Extraction runs on-device through the NewPipe Extractor engine bundled in
/// the vendored Android plugin (the upstream `get_video_info`-based extractor
/// stopped working when YouTube removed that endpoint). Returns the direct
/// media URL for the requested itag (18 = 360p progressive mp4), or the
/// extractor's error text when extraction fails.
class FlutterYoutubeDownloader {
  static const MethodChannel _channel = MethodChannel('flutter_youtube_downloader');

  static Future<dynamic> downloadVideo(
      String youTubeVideoUrl, String title, int? videoItag) async {
    try {
      final result = await _channel.invokeMethod('downloadVideo', {
        "url": youTubeVideoUrl,
        "title": title,
        "itag": videoItag == null ? 18 : videoItag,
      });
      return result;
    } on PlatformException catch (e) {
      return e.message;
    }
  }

  static Future<dynamic> extractYoutubeLink(
      String youTubeVideoUrl, int? videoItag) async {
    try {
      final result = await _channel.invokeMethod('extractYoutubeLink', {
        "url": youTubeVideoUrl,
        "itag": videoItag == null ? 18 : videoItag,
      });
      return result;
    } on PlatformException catch (e) {
      return e.message;
    }
  }
}
