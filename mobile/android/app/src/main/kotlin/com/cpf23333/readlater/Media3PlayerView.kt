package com.cpf23333.readlater

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.webkit.CookieManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** 用 Media3 ExoPlayer 播放网页里检测到的视频地址。 */
class Media3PlayerViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<*, *>)?.entries
            ?.associate { (it.key as? String).orEmpty() to (it.value?.toString() ?: "") }
            ?: emptyMap()
        return Media3PlayerView(context, params)
    }
}

class Media3PlayerView(
    context: Context,
    params: Map<String, String>,
) : PlatformView {
    private val root = FrameLayout(context)
    private val playerView = PlayerView(context)
    private val errorView = TextView(context)
    private val player: ExoPlayer

    init {
        playerView.setBackgroundColor(Color.BLACK)
        playerView.setKeepScreenOn(true)
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
        playerView.setControllerShowTimeoutMs(3000)
        root.addView(playerView, FrameLayout.LayoutParams(-1, -1))

        errorView.visibility = View.GONE
        errorView.setTextColor(Color.WHITE)
        errorView.textSize = 16f
        errorView.setPadding(48, 48, 48, 48)
        root.addView(errorView, FrameLayout.LayoutParams(-1, -1))

        val url = params["url"].orEmpty()
        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)

        val headers = mutableMapOf<String, String>()
        params["userAgent"]?.takeIf { it.isNotBlank() }?.let { headers["User-Agent"] = it }
        params["referer"]?.takeIf { it.isNotBlank() }?.let { headers["Referer"] = it }
        if (url.isNotBlank()) {
            // 复用 WebView 的 Cookie，很多站点缺 Cookie 会 403。
            CookieManager.getInstance().getCookie(url)?.takeIf { it.isNotBlank() }?.let {
                headers["Cookie"] = it
            }
        }
        if (headers.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }

        player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(context).setDataSourceFactory(httpFactory),
            )
            .build()
        playerView.player = player
        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                showError("播放失败：${error.errorCodeName}\n${error.message.orEmpty()}")
            }
        })

        if (url.isBlank()) {
            showError("没有可播放的视频地址")
        } else {
            player.setMediaItem(MediaItem.Builder().setUri(Uri.parse(url)).build())
            player.prepare()
            player.playWhenReady = true
        }
    }

    private fun showError(message: String) {
        errorView.text = message
        errorView.visibility = View.VISIBLE
    }

    override fun getView(): View = root

    override fun dispose() {
        playerView.player = null
        player.release()
    }
}
