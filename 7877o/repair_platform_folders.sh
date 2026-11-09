#!/usr/bin/env bash
# ONLY needed if `flutter run` complains about Gradle/Android/iOS project files (e.g. very old Flutter).
# Rebuilds android/ and ios/ with YOUR installed Flutter. Run: bash repair_platform_folders.sh
set -e
cd "$(dirname "$0")/mobile_app"
mkdir -p ../.bak && cp -r lib ../.bak/lib && cp pubspec.yaml ../.bak/pubspec.yaml
rm -rf android ios
flutter create --org com.graphen --project-name graphenbags --platforms=android,ios .
rm -rf lib test && cp -r ../.bak/lib lib && cp ../.bak/pubspec.yaml pubspec.yaml && rm -rf ../.bak
M=android/app/src/main/AndroidManifest.xml
grep -q android.permission.INTERNET "$M" || perl -0pi -e 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
perl -pi -e 's#android:label="[^"]*"#android:label="Graphen Bags"#' "$M"
flutter pub get
echo "Repaired. Now run: flutter run"
