# ERM Final Bundle Bar Counter — Windows project

Flutter desktop source for a Windows bundle-counting prototype. Open a JPEG or PNG photo, adjust the reference circle to a typical end, select sensitivity and press Suggest bars. Review markers using Add/Remove and save the result. For multiple bundles in one image, crop to the intended bundle before importing.

## Build on Windows

Install Flutter 3.47.9 or a compatible newer version and Visual Studio 2022 with the Desktop development with C++ workload and Windows SDK. In PowerShell:

```
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

The executable and required DLLs will be in `build\windows\x64\runner\Release\`. Copy the **entire Release folder** to the target computer. This archive does not include a prebuilt executable. Local data is stored on the Windows computer. Photo import uses the native file picker.

## Detector and limitations

The experimental offline gradient-circle detector now searches seven radius scales from 72% to 128% of the selected reference radius. This improves coverage of differently sized synthetic circles; it also increases computation and may increase false detections in clutter. The sensitivity slider and manual marker review remain essential. Hidden ends cannot be detected. The supplied reference images were visible in the conversation but were not available as files in the build environment, so detection accuracy on those exact images was not measured. Do not use the result as an accepted inventory count without human verification.

Validation on Linux: Flutter analysis passed and 11 tests passed, including 12 of 12 synthetic mixed-size circles. No Windows build, Windows file-picker test, actual site-photo accuracy test, or physical-device test was performed.
