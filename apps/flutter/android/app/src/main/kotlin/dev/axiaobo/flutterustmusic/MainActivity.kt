package dev.axiaobo.flutterustmusic

import android.os.Bundle
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
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
