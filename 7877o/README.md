# Graphen Bags - mobile app (Flutter, Android + iOS)

Ready to run. Supabase is already connected in lib/config.dart.

    flutter pub get
    flutter run                     # pick your phone/emulator
    flutter build apk --release     # Android APK
    flutter build ipa               # iOS (needs a Mac + Apple developer account)

Package / bundle ID: com.graphen.graphenbags  (change before publishing if you want a different one).
Requires the current Flutter stable (the Android/iOS project files were generated for it). If Gradle or
Xcode complain, run repair_platform_folders.bat (Windows) or repair_platform_folders.sh (Mac/Linux) from this folder.
Play Store releases need your own signing key; the project currently signs release builds with the debug key.
