package com.destinyed.flutter_youtube_downloader;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import org.schabi.newpipe.extractor.MediaFormat;
import org.schabi.newpipe.extractor.NewPipe;
import org.schabi.newpipe.extractor.ServiceList;
import org.schabi.newpipe.extractor.stream.StreamExtractor;
import org.schabi.newpipe.extractor.stream.VideoStream;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * FlutterYoutubeDownloaderPlugin — vendored rewrite of the upstream 0.0.5
 * plugin. The upstream engine (at.huber.youtubeExtractor) relies on the
 * retired get_video_info endpoint, so extraction now runs through the
 * actively maintained NewPipe Extractor instead. The Dart-facing API is
 * unchanged: extractYoutubeLink(url, itag) and downloadVideo(url, title, itag).
 */
public class FlutterYoutubeDownloaderPlugin implements FlutterPlugin, MethodCallHandler {

    private MethodChannel channel;
    private Context appContext;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(final FlutterPlugin.FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_youtube_downloader");
        channel.setMethodCallHandler(this);
        appContext = binding.getApplicationContext();
        try {
            NewPipe.init(new SimpleDownloader());
        } catch (final Throwable t) {
            // Never crash the engine over an init problem — extraction will
            // surface a proper error message through the channel instead.
        }
    }

    @Override
    public void onMethodCall(final MethodCall call, final Result result) {
        final String url = call.argument("url");
        final String title = call.argument("title");
        final Integer itagArg = call.argument("itag");
        final int itag = itagArg == null ? 18 : itagArg;

        if ("extractYoutubeLink".equals(call.method)) {
            extractAsync(url, itag, title, false, result);
        } else if ("downloadVideo".equals(call.method)) {
            extractAsync(url, itag, title, true, result);
        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onDetachedFromEngine(final FlutterPlugin.FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }

    private void extractAsync(final String url, final int itag, final String title,
                              final boolean thenDownload, final Result result) {
        executor.execute(new Runnable() {
            @Override
            public void run() {
                String link = null;
                String error = null;
                try {
                    final StreamExtractor ext = ServiceList.YouTube.getStreamExtractor(url);
                    ext.fetchPage();
                    final List<VideoStream> streams = ext.getVideoStreams();
                    VideoStream chosen = null;
                    for (final VideoStream s : streams) {
                        if (s.isVideoOnly() || s.getFormat() != MediaFormat.MPEG_4) {
                            continue;
                        }
                        if (s.getItag() == itag) {
                            chosen = s;
                            break;
                        }
                    }
                    if (chosen == null) {
                        // Requested itag unavailable — fall back to the best
                        // progressive MP4 (video + audio in one file).
                        int best = -1;
                        for (final VideoStream s : streams) {
                            if (s.isVideoOnly() || s.getFormat() != MediaFormat.MPEG_4) {
                                continue;
                            }
                            if (s.getHeight() > best) {
                                best = s.getHeight();
                                chosen = s;
                            }
                        }
                    }
                    if (chosen != null) {
                        link = chosen.getContent();
                    }
                    if (link == null || link.isEmpty()) {
                        error = "No progressive MP4 stream (itag " + itag + ") found";
                    }
                } catch (final Throwable t) {
                    error = t.getMessage() == null ? t.getClass().getSimpleName() : t.getMessage();
                }

                final String linkF = link;
                final String errorF = error;
                main.post(new Runnable() {
                    @Override
                    public void run() {
                        if (errorF != null) {
                            result.error("EXTRACT_FAIL", errorF, null);
                        } else if (thenDownload) {
                            result.success(linkF);
                            new DownloadManagerClass(appContext)
                                    .download(title == null || title.isEmpty() ? "video" : title, "Pips video", linkF);
                        } else {
                            result.success(linkF);
                        }
                    }
                });
            }
        });
    }
}
