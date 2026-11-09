@echo off
rem ONLY needed if "flutter run" complains about Gradle/Android/iOS project files (e.g. very old Flutter).
cd /d "%~dp0mobile_app"
mkdir ..\bak
xcopy /e /i /q lib ..\bak\lib >nul
copy /y pubspec.yaml ..\bak\pubspec.yaml >nul
rmdir /s /q android
rmdir /s /q ios
call flutter create --org com.graphen --project-name graphenbags --platforms=android,ios .
rmdir /s /q lib
rmdir /s /q test
xcopy /e /i /q ..\bak\lib lib >nul
copy /y ..\bak\pubspec.yaml pubspec.yaml >nul
rmdir /s /q ..\bak
powershell -NoProfile -Command "$m='android\app\src\main\AndroidManifest.xml'; $t=Get-Content $m -Raw; if($t -notmatch 'permission.INTERNET'){ $t=$t -replace '<application','<uses-permission android:name=\"android.permission.INTERNET\"/>`n    <application' }; $t=$t -replace 'android:label=\"[^\"]*\"','android:label=\"Graphen Bags\"'; Set-Content $m $t -NoNewline"
call flutter pub get
echo Repaired. Now run: flutter run
pause
