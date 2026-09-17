package com.destinyed.flutter_youtube_downloader;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;
import android.widget.Toast;

/** Hands the direct media URL to the system DownloadManager (downloadVideo path). */
public class DownloadManagerClass {

    private final Context ctx;

    public DownloadManagerClass(final Context ctx) {
        this.ctx = ctx;
    }

    public void download(final String nTitle, final String nDescription, final String nUrl) {
        try {
            final DownloadManager dm =
                    (DownloadManager) ctx.getSystemService(Context.DOWNLOAD_SERVICE);
            if (dm == null) {
                return;
            }
            final String safeTitle = nTitle == null || nTitle.isEmpty()
                    ? "video" : nTitle.replaceAll("[^a-zA-Z0-9 ._\\-]", "_");

            final DownloadManager.Request req = new DownloadManager.Request(Uri.parse(nUrl));
            req.setTitle(safeTitle);
            req.setDescription(nDescription);
            req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeTitle + ".mp4");
            req.setMimeType("video/mp4");
            dm.enqueue(req);
            Toast.makeText(ctx, "Video is downloading… slide down to see progress", Toast.LENGTH_LONG).show();
        } catch (final Exception e) {
            Toast.makeText(ctx, "Download link is broken or not available: " + e.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }
}
