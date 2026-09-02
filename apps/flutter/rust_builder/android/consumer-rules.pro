# Rust loads this verifier through the Android application class loader.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
