use jni::{EnvUnowned, objects::JObject};

/// Initializes rustls with Android's application context before any HTTPS request.
///
/// The matching native method is invoked by `FuraApplication` during process
/// startup. `EnvUnowned::with_env` prevents JNI errors or panics from crossing
/// the native boundary and reports initialization failures to Android.
#[unsafe(no_mangle)]
#[allow(non_snake_case)]
pub extern "system" fn Java_dev_axiaobo_flutterustmusic_FuraApplication_initializeRustlsPlatformVerifier<
    'caller,
>(
    mut unowned_env: EnvUnowned<'caller>,
    _application: JObject<'caller>,
    context: JObject<'caller>,
) {
    let outcome =
        unowned_env.with_env(|env| rustls_platform_verifier::android::init_with_env(env, context));
    outcome.resolve::<jni::errors::ThrowRuntimeExAndDefault>();
}
