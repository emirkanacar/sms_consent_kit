# Contributing

## Development environment

- Flutter stable (development uses 3.50), JDK 17
- `flutter pub get && (cd example && flutter pub get)`

## Common commands

```bash
dart format .
flutter analyze && (cd example && flutter analyze)
flutter test && (cd example && flutter test)
(cd example/android && ./gradlew :sms_consent_kit:testDebugUnitTest)
```

## Pigeon

The Dart ↔ Kotlin bridge is generated from `pigeon/messages.dart`. After
changing the schema, run:

```bash
tool/generate_pigeon.sh
```

The generated `lib/src/transport/messages.g.dart` and
`android/src/main/kotlin/.../Messages.g.kt` files are committed; CI checks
that they are up to date. Do not edit these files by hand.

## Android dependencies

The versions in `android/build.gradle.kts` are **lower bounds** and are kept
low on purpose (e.g. `androidx.core` 1.15+ forces consumer apps onto
compileSdk 35+). Before bumping one, check the `minCompileSdk` and
`minSdkVersion` values in the AAR metadata.

## Language

All code, comments, documentation, commit messages and issues are in English.

## Documentation

Every PR that changes behavior updates the related `doc/` file (especially
`doc/EDGE_CASES.md`).
