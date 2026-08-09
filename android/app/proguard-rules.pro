# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Flutter plugins
-keep class com.freya.freya_pdf.** { *; }

# http / dart
-dontwarn javax.annotation.**
-keep class dart._  { *; }

# Encrypt library (AES-GCM)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Lottie
-keep class com.airbnb.lottie.** { *; }
