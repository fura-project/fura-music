# Flutter localization

HD-026 localizes the first-party Flutter presentation with the official Flutter
`gen_l10n` pipeline. English is the template language and Simplified Chinese is
the first additional candidate catalog pending Human language review.

## Ownership

- `apps/flutter/lib/l10n/app_en.arb` is the source template and documents
  placeholder intent where a message is ambiguous, dynamic, destructive, or
  accessibility-sensitive.
- `apps/flutter/lib/l10n/app_zh.arb` contains the Simplified Chinese candidate
  catalog. The generator requires this generic-language parent for script
  variants; `app_zh_Hans.arb` declares `zh_Hans`, and its generated class
  inherits the complete Chinese catalog. Product locale resolution never uses
  this topology to opt Traditional Chinese into Simplified Chinese.
- Generated `app_localizations*.dart` files are tool output. Never edit them by
  hand; run `flutter gen-l10n` after changing ARB catalogs.
- Flutter presentation maps typed errors and semantic enums to localized copy.
  Rust and the typed Bridge never receive locale state or presentation strings.

## Locale behavior

Settings persists one of `system`, `english`, or `simplifiedChinese`. Existing
schema versions 1–3 migrate to `system`. An unknown schema-v4 locale value also
falls back to `system` while preserving other valid settings.

The system resolver maps English to English; generic Chinese, `zh-Hans`,
`zh-CN`, and `zh-SG` to Simplified Chinese; and `zh-Hant`, `zh-TW`, `zh-HK`, and
`zh-MO` to English. Unsupported languages fall back to English. Manual language
selection ignores later operating-system changes until the user selects
Follow system again.

## Translation boundary

Translate Fura-authored titles, labels, hints, dialogs, snackbars, failures,
tooltips, semantic labels, live-region announcements, and date/number phrases.
Do not translate Provider-returned song, Artist, Album, Playlist, comment or
lyric content; Provider IDs; opaque identities; logs; protocol errors; URLs;
MIME/codec values; or stable abbreviations such as HQ and SQ.

Android AudioService configuration is created before `runApp` and currently
retains its stable product/service strings. Moving those strings behind a
locale-aware native startup contract is a separate platform task and must not
recreate the app-lifetime playback owner.

## Verification

Run from `apps/flutter`:

```text
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test integration_test
dart analyze
flutter test
flutter build linux --release
flutter build apk --release --target-platform android-arm64
```

Review artifacts remain evidence for Human assessment; they do not establish
translation quality or visual acceptance on their own.

The 2026-09-12 machine checkpoint has 843 matching English and Simplified
Chinese messages. The English template provides metadata for all 194 dynamic
messages, including 14 plural/select messages, and additional static metadata
for ambiguous, destructive and accessibility-sensitive copy. `flutter
gen-l10n`, formatting of 246 Dart files, `dart analyze`, all 552 Flutter tests,
the native Settings persistence integration test, Linux Release and Android
ARM64 Release pass. Human acceptance of the candidate Chinese wording and final
visual rhythm remains open.

The static audit distinguishes authored presentation copy from stable brand and
protocol values. Expected literals that remain outside ARB include `fura music`,
`MV`, `HQ`, `SQ`, `STD`, table numbering, test fixture data, internal keys and
diagnostic/log strings. A literal is not exempt merely because it is short:
buttons, tooltips, semantic labels, live-region announcements and typed failure
messages belong in ARB.

The MPRIS metadata model's internal `No track` sentinel is not emitted: an empty
item serializes to an empty metadata dictionary. DBus validation errors are
protocol diagnostics rather than product presentation. These exceptions must
not be reused as a route for user-visible copy.

## Adding a locale

To add a future locale such as Japanese without replacing this architecture:

1. Add `lib/l10n/app_ja.arb` and translate every English template key with the
   same ICU placeholders and plural arguments.
2. Run `flutter gen-l10n`; the generated delegate adds the locale to its
   supported set. Add an explicit resolution rule when script or region
   fallback could otherwise be ambiguous.
3. Add a new `AppLocalePreference` and Settings option only if the locale is a
   user-selectable manual override. Update schema parsing without invalidating
   existing documents; a schema bump is needed only when the persisted model
   changes.
4. Extend direct catalog, resolver, Settings-search and runtime-switch tests.
   Add the locale to the compact/desktop and Provider review matrix, including
   large-text and accessibility checks.
5. Obtain Human copy and visual acceptance. Machine generation and layout
   success do not certify translation quality.
