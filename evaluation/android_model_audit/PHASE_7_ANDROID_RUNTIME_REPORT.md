# Phase 7 Android runtime report

The app was not installed and was not launched. Compilation and static `aapt` reads are not a PASS.

## Emulator blocker

Host: Ubuntu 24.04.5 on Linux x86_64. This is not an Apple Silicon Mac. No macOS KVM change was attempted.

Commands and errors:

```
$ python3 -c 'import os; os.open("/dev/kvm", os.O_RDWR)'
OPEN_FAIL errno=13 EACCES [Errno 13] Permission denied: '/dev/kvm'

$ ls -l /dev/kvm
crw-rw---- 1 root ssl-cert 10, 232 Nov  4 00:44 /dev/kvm

$ id
uid=1000(ubuntu) groups do not include ssl-cert

$ ls /home/ubuntu/Android/Sdk/emulator/emulator
ls: cannot access '/home/ubuntu/Android/Sdk/emulator/emulator': No such file or directory

$ ls /home/ubuntu/Android/Sdk/system-images
No such file or directory

$ adb devices -l
List of devices attached
```

`emulator` is not on `PATH` and the SDK emulator package is not installed. There is no system image. Even if an image were downloaded, this user cannot open `/dev/kvm`. Status: BLOCKED. The emulator did not run.

## Apple Silicon steps (not executed here)

1. Install Android Studio. In SDK Manager install Android SDK Platform 36. This app's minSdk is 24, targetSdk and compileSdk are 36.
2. Install an arm64-v8a system image for API 36 (Google APIs). Do not use an x86_64 image.
3. Device Manager → Create Virtual Device → phone → that arm64 image. Boot it. `adb shell getprop ro.product.cpu.abi` must print `arm64-v8a`. The Mac hypervisor is what boots that AVD. This container's `/dev/kvm` is irrelevant there.
4. `adb install -r app-arm64-v8a-release.apk` from `app/build/app/outputs/flutter-apk/`. Do not install the armeabi-v7a or x86_64 split on that emulator.
5. Walk the checklist below. A physical phone is still required before Play.

## Checklist

| Check | Result | Evidence |
| --- | --- | --- |
| Install ARM64 release APK | NOT EXECUTED | `adb devices` was empty. No `adb install` |
| Launch / main screen | NOT EXECUTED | No process |
| logcat crashes, missing assets, native libs, TFLite init | NOT EXECUTED | No logcat |
| Camera permission grant | NOT EXECUTED | |
| Camera permission deny | NOT EXECUTED | |
| Camera preview | NOT EXECUTED | |
| Gallery | NOT EXECUTED | |
| Inference | NOT EXECUTED | |
| Detection display | NOT EXECUTED | |
| Confidence threshold persistence | NOT EXECUTED | Host unit tests exist; they are not this check |
| Offline / pending sync | NOT EXECUTED | |
| Retry after network restore | NOT EXECUTED | No non-production server was contacted |
| Resume / restart with pending sync | NOT EXECUTED | |
| Media permission | NOT EXECUTED | |

Static facts that are not runtime PASSes: the merged release manifest still declares `CAMERA`, `INTERNET`, fine and coarse location, `READ_EXTERNAL_STORAGE`, and `WRITE_EXTERNAL_STORAGE` with maxSdk 28. `RECORD_AUDIO` is absent. `android:allowBackup` is false and `usesCleartextTraffic` is false. The release binary manifest has no `debuggable` attribute.

Lifecycle code was read (`camera_detection_screen.dart` init, dispose, and `didChangeAppLifecycleState`; interpreter `close()`). No Android log showed a leak or a crash, so nothing was patched.
