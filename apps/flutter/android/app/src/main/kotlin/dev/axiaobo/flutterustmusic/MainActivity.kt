package dev.axiaobo.flutterustmusic

import android.content.Context
import android.os.Bundle
import android.util.Log
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        if (BuildConfig.USE_AUDIO_SERVICE_SYSTEM_EDGE) {
            AudioServicePlugin.getFlutterEngine(context)
        } else {
            super.provideFlutterEngine(context)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(diagnosticTag, "phase=activity_on_create outcome=started")
        try {
            super.onCreate(savedInstanceState)
            Log.i(diagnosticTag, "phase=activity_on_create outcome=success")
        } catch (error: Throwable) {
            Log.e(
                diagnosticTag,
                "phase=activity_on_create outcome=failed exceptionClass=${error.javaClass.name}",
            )
            throw error
        }
    }

    companion object {
        private const val diagnosticTag = "FURA_DIAGNOSTIC_ANDROID"
    }
}
