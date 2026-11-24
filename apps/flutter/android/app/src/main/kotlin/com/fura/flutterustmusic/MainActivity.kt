package com.fura.flutterustmusic

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

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

    override fun onPause() {
        super.onPause()
        Log.i(diagnosticTag, "phase=activity_paused outcome=success")
    }

    override fun onResume() {
        super.onResume()
        Log.i(diagnosticTag, "phase=activity_resumed outcome=success")
    }

    companion object {
        private const val diagnosticTag = "FURA_DIAGNOSTIC_ANDROID"
    }
}
