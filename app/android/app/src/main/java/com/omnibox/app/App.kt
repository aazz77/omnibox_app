package com.omnibox.app

import android.app.Application
import android.content.Context
import com.omnibox.app.core.Api
import com.omnibox.app.core.AppSettings
import com.omnibox.app.core.IptvStore

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        context = applicationContext
        val dataDir = "${filesDir.path}/omnibox_data"
        java.io.File(dataDir).mkdirs()
        Api.init(dataDir)
        AppSettings.init(this)
        IptvStore.init(this)
    }

    companion object {
        lateinit var context: Context
            private set
    }
}
