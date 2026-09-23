package dev.axiaobo.flutterustmusic

import android.app.Application
import android.content.Context
import android.util.Log

class FuraApplication : Application() {
    override fun onCreate() {
        diagnostic(phase = "application_on_create", outcome = "started")
        try {
            super.onCreate()
        } catch (error: Throwable) {
            diagnosticFailure(phase = "application_on_create", error = error)
            throw error
        }

        diagnostic(phase = "rustls_verifier_init", outcome = "started")
        try {
            initializeRustlsPlatformVerifier(applicationContext)
            diagnostic(phase = "rustls_verifier_init", outcome = "success")
        } catch (error: Throwable) {
            diagnosticFailure(phase = "rustls_verifier_init", error = error)
            throw error
        }
        diagnostic(phase = "application_on_create", outcome = "success")
    }

    private external fun initializeRustlsPlatformVerifier(context: Context)

    companion object {
        init {
            diagnostic(phase = "rust_library_load", outcome = "started")
            try {
                System.loadLibrary("rust_lib_flutterustmusic")
                diagnostic(phase = "rust_library_load", outcome = "success")
            } catch (error: Throwable) {
                diagnosticFailure(phase = "rust_library_load", error = error)
                throw error
            }
        }

        private const val diagnosticTag = "FURA_DIAGNOSTIC_ANDROID"

        private fun diagnostic(phase: String, outcome: String) {
            Log.i(diagnosticTag, "phase=$phase outcome=$outcome")
        }

        private fun diagnosticFailure(phase: String, error: Throwable) {
            Log.e(
                diagnosticTag,
                "phase=$phase outcome=failed exceptionClass=${error.javaClass.name}",
            )
        }
    }
}
