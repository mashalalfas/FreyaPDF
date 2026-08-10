# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Flutter plugins
-keep class com.freya.freya_pdf.** { *; }

# http / dart
# Dart AOT classes (dart._) are compiled into the kernel blob and do not need
# Java-side keep rules; omitting the catch-all lets R8 obfuscate the native
# shell more aggressively. Removing this rule was verified against a release
# build (see audit-fix commit).
-dontwarn javax.annotation.**

# Encrypt library (AES-GCM)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Lottie
-keep class com.airbnb.lottie.** { *; }
