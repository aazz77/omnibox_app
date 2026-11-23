package com.omnibox.app.ui.music

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.omnibox.app.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** 音乐前台服务：保活播放 + 通知栏控制 */
class MusicService : Service() {
    private val job = SupervisorJob()
    private val scope = CoroutineScope(job + Dispatchers.Main)

    companion object {
        const val CHANNEL_ID = "omnibox_music"
        const val ACTION_PLAY_PAUSE = "play_pause"
        const val ACTION_NEXT = "next"
        const val ACTION_PREVIOUS = "previous"
        const val ACTION_STOP = "stop"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        MusicPlayerRepository.init(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> MusicPlayerRepository.playPause()
            ACTION_NEXT -> MusicPlayerRepository.next()
            ACTION_PREVIOUS -> MusicPlayerRepository.previous()
            ACTION_STOP -> { MusicPlayerRepository.pause(); stopSelf(); return START_NOT_STICKY }
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "OmniBox 音乐"
        val artist = intent?.getStringExtra(EXTRA_ARTIST) ?: ""
        startForeground(1, buildNotification(title, artist))
        return START_STICKY
    }

    private fun createChannel() {
        val mgr = getSystemService(NotificationManager::class.java)
        val ch = NotificationChannel(CHANNEL_ID, "音乐播放", NotificationManager.IMPORTANCE_LOW)
        mgr.createNotificationChannel(ch)
    }

    private fun buildNotification(title: String, artist: String): android.app.Notification {
        val openIntent = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        fun action(icon: Int, text: String, act: String): NotificationCompat.Action {
            val pi = PendingIntent.getService(this, act.hashCode(),
                Intent(this, MusicService::class.java).setAction(act), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            return NotificationCompat.Action(icon, text, pi)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(openIntent)
            .setOnlyAlertOnce(true)
            .addAction(action(android.R.drawable.ic_media_pause, "播放/暂停", ACTION_PLAY_PAUSE))
            .addAction(action(android.R.drawable.ic_media_next, "下一首", ACTION_NEXT))
            .addAction(action(android.R.drawable.ic_media_previous, "上一首", ACTION_PREVIOUS))
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        super.onDestroy()
        job.cancel()
    }
}

fun startMusicService(title: String, artist: String) {
    val ctx = com.omnibox.app.App.context
    val intent = Intent(ctx, MusicService::class.java).apply {
        putExtra(MusicService.EXTRA_TITLE, title)
        putExtra(MusicService.EXTRA_ARTIST, artist)
    }
    ctx.startForegroundService(intent)
}
