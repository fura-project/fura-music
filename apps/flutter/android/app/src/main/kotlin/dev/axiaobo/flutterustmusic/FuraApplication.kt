package dev.axiaobo.flutterustmusic

import android.app.Application
import android.content.Context

class FuraApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        initializeRustlsPlatformVerifier(applicationContext)
    }

    private external fun initializeRustlsPlatformVerifier(context: Context)

    companion object {
        init {
            System.loadLibrary("rust_lib_flutterustmusic")
        }
    }
}
