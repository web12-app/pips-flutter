package com.destinyed.flutter_youtube_downloader;

import org.schabi.newpipe.extractor.downloader.Downloader;
import org.schabi.newpipe.extractor.downloader.Request;
import org.schabi.newpipe.extractor.downloader.Response;
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;
import java.util.Map;

/**
 * Minimal NewPipe Extractor Downloader backed by HttpURLConnection — no
 * external HTTP dependency, works with the requests the YouTube extractor
 * issues (watch page HTML, InnerTube JSON POSTs, player JS).
 */
public class SimpleDownloader extends Downloader {

    private static final String UA =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) "
                    + "Chrome/124.0.0.0 Mobile Safari/537.36";

    @Override
    public Response execute(final Request request) throws IOException, ReCaptchaException {
        final HttpURLConnection conn =
                (HttpURLConnection) new URL(request.url()).openConnection();
        conn.setRequestMethod(request.httpMethod());
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("User-Agent", UA);

        final Map<String, List<String>> headers = request.headers();
        if (headers != null) {
            for (final Map.Entry<String, List<String>> e : headers.entrySet()) {
                if (e.getKey() == null || e.getValue() == null || e.getValue().isEmpty()) {
                    continue;
                }
                conn.setRequestProperty(e.getKey(), String.join("; ", e.getValue()));
            }
        }

        final byte[] data = request.dataToSend();
        if (data != null && data.length > 0) {
            conn.setDoOutput(true);
            OutputStream os = null;
            try {
                os = conn.getOutputStream();
                os.write(data);
                os.flush();
            } finally {
                if (os != null) {
                    os.close();
                }
            }
        }

        final int code = conn.getResponseCode();
        InputStream is = null;
        try {
            is = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
        } catch (final IOException ignored) {
            is = null;
        }

        String body = "";
        if (is != null) {
            final ByteArrayOutputStream bos = new ByteArrayOutputStream();
            final byte[] buf = new byte[8192];
            int n;
            while ((n = is.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            is.close();
            body = bos.toString("UTF-8");
        }

        return new Response(code, conn.getResponseMessage(), conn.getHeaderFields(),
                body, conn.getURL().toString());
    }
}
