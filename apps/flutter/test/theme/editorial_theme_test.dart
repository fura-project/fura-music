import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/adaptive_side_sheet.dart';
import 'package:flutterustmusic/catalog/music_collection_detail_layout.dart';
import 'package:flutterustmusic/discover/ranking_page.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/library/library_collection_header.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_controller.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_panel.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/now_playing_bar.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';
import 'package:flutterustmusic/settings/settings_page.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

double _contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

void main() {
  group('MusicEditorialTheme tokens and ThemeData', () {
    test('light and dark editorial themes expose curated archival tokens', () {
      final lightTheme = MusicMaterialTheme.light(
        visualStyle: AppVisualStyle.editorial,
      );
      final darkTheme = MusicMaterialTheme.dark(
        visualStyle: AppVisualStyle.editorial,
      );
      final standardLight = MusicMaterialTheme.light();
      final standardDark = MusicMaterialTheme.dark();

      final lightTokens = lightTheme.extension<MusicEditorialTheme>();
      final darkTokens = darkTheme.extension<MusicEditorialTheme>();
      expect(lightTokens, isNotNull);
      expect(darkTokens, isNotNull);
      expect(lightTokens!.isEditorial, isTrue);
      expect(darkTokens!.isEditorial, isTrue);
      expect(standardLight.extension<MusicEditorialTheme>(), isNull);
      expect(standardDark.extension<MusicEditorialTheme>(), isNull);

      for (final theme in [lightTheme, darkTheme]) {
        final colors = theme.colorScheme;
        final tokens = theme.extension<MusicEditorialTheme>()!;
        expect(theme.useMaterial3, isTrue);
        expect(theme.scaffoldBackgroundColor, tokens.paperCanvas);
        expect(theme.appBarTheme.backgroundColor, tokens.paperCanvas);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(
          theme.textTheme.headlineLarge?.fontFamily,
          editorialSerifFontFamily,
        );
        expect(
          theme.textTheme.headlineLarge?.fontFamilyFallback,
          contains('Noto Serif CJK SC'),
        );
        expect(
          theme.textTheme.titleLarge?.fontFamily,
          editorialSerifFontFamily,
        );
        expect(tokens.cardRadius, const BorderRadius.all(Radius.circular(4)));
        expect(
          tokens.artworkRadius,
          const BorderRadius.all(Radius.circular(4)),
        );
        expect(
          _contrastRatio(colors.onSurface, colors.surface),
          greaterThanOrEqualTo(12.0),
        );
        expect(
          _contrastRatio(colors.onSurfaceVariant, colors.surfaceContainerLow),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(10.0),
        );
        expect(
          _contrastRatio(
            theme.snackBarTheme.contentTextStyle!.color!,
            theme.snackBarTheme.backgroundColor!,
          ),
          greaterThanOrEqualTo(10.0),
        );
        expect(
          _contrastRatio(
            theme.snackBarTheme.actionTextColor!,
            theme.snackBarTheme.backgroundColor!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(theme.tabBarTheme.indicatorColor, tokens.inkPrimary);
        expect(theme.tabBarTheme.dividerColor, tokens.hairline);
        expect(theme.segmentedButtonTheme.style, isNotNull);
        expect(theme.chipTheme.backgroundColor, tokens.cardSurface);
        expect(theme.tooltipTheme.decoration, isA<BoxDecoration>());
      }

      // Light archival linen paper vs dark nocturne charcoal paper.
      expect(
        lightTheme.colorScheme.surface.computeLuminance(),
        greaterThan(0.9),
      );
      expect(darkTheme.colorScheme.surface.computeLuminance(), lessThan(0.03));
    });

    test('MusicEditorialTheme copyWith and lerp interpolate cleanly', () {
      final copied = MusicEditorialTheme.editorialLight.copyWith(
        paperCanvas: const Color(0xFFFFFDF8),
      );
      expect(copied.paperCanvas, const Color(0xFFFFFDF8));
      expect(copied.isEditorial, isTrue);

      final mid = MusicEditorialTheme.editorialLight.lerp(
        MusicEditorialTheme.editorialDark,
        0.5,
      );
      expect(mid.isEditorial, isTrue);
      expect(
        mid.paperCanvas,
        isNot(MusicEditorialTheme.editorialLight.paperCanvas),
      );
      expect(
        mid.paperCanvas,
        isNot(MusicEditorialTheme.editorialDark.paperCanvas),
      );
    });

    testWidgets(
      'searchDecoration switches from capsule in Material to hairline frame in Editorial',
      (tester) async {
        late InputDecoration materialDecoration;
        late InputDecoration editorialDecoration;

        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(),
            home: Builder(
              builder: (context) {
                materialDecoration = MusicMaterialTheme.searchDecoration(
                  context,
                  hintText: 'Search',
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final materialBorder =
            materialDecoration.enabledBorder! as OutlineInputBorder;
        expect(materialBorder.borderSide, BorderSide.none);
        expect(materialBorder.borderRadius, BorderRadius.circular(999));

        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(
              visualStyle: AppVisualStyle.editorial,
            ),
            home: Builder(
              builder: (context) {
                editorialDecoration = MusicMaterialTheme.searchDecoration(
                  context,
                  hintText: 'Search',
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editorialBorder =
            editorialDecoration.enabledBorder! as OutlineInputBorder;
        expect(editorialBorder.borderSide, isNot(BorderSide.none));
        expect(
          editorialBorder.borderRadius,
          MusicEditorialTheme.editorialLight.controlRadius,
        );
      },
    );
  });

  group('AppSettings visualStyle persistence and migration', () {
    test(
      'round-trips AppVisualStyle.editorial and defaults to material',
      () async {
        final storage = _MemorySettingsStorage();
        final store = AppSettingsStore(storage: storage);

        expect(AppSettings.defaults.visualStyle, AppVisualStyle.material);

        const editorialSettings = AppSettings(
          theme: AppThemePreference.dark,
          visualStyle: AppVisualStyle.editorial,
          colorSource: AppColorSourcePreference.brand,
          playbackQuality: AppPlaybackQualityPreference.lossless,
          lyricAuxiliaryMode: LyricAuxiliaryMode.translation,
          musicProvider: AppMusicProvider.netEaseCloudMusic,
          localePreference: AppLocalePreference.simplifiedChinese,
        );

        expect(
          await store.save(editorialSettings),
          AppSettingsWriteResult.saved,
        );
        final encoded = jsonDecode(storage.document!) as Map<String, dynamic>;
        expect(encoded['schemaVersion'], AppSettings.currentSchemaVersion);
        expect(encoded['visualStyle'], 'editorial');

        final loaded = await store.load();
        expect(loaded.state, AppSettingsLoadState.stored);
        expect(loaded.settings, editorialSettings);
      },
    );

    test(
      'migrates schemaVersion 6 documents safely to AppVisualStyle.material',
      () async {
        final storage = _MemorySettingsStorage(
          document: jsonEncode(<String, Object>{
            'schemaVersion': 6,
            'theme': 'light',
            'colorSource': 'system',
            'playbackQuality': 'high',
            'lyricAuxiliaryMode': 'romanization',
            'musicProvider': 'qqMusic',
            'localePreference': 'english',
          }),
        );
        final loaded = await AppSettingsStore(storage: storage).load();
        expect(loaded.state, AppSettingsLoadState.migrated);
        expect(loaded.settings.visualStyle, AppVisualStyle.material);
        expect(loaded.settings.theme, AppThemePreference.light);
        expect(loaded.settings.colorSource, AppColorSourcePreference.system);
        expect(
          loaded.settings.lyricAuxiliaryMode,
          LyricAuxiliaryMode.romanization,
        );
      },
    );

    test('unknown visualStyle falls back safely to material and requests migration', () async {
      final storage = _MemorySettingsStorage(
        document: jsonEncode(<String, Object>{
          'schemaVersion': AppSettings.currentSchemaVersion,
          'theme': 'dark',
          'colorSource': 'brand',
          'visualStyle': 'futureTypography',
          'playbackQuality': 'standard',
          'lyricAuxiliaryMode': 'auto',
          'musicProvider': 'qqMusic',
          'localePreference': 'system',
        }),
      );
      final loaded = await AppSettingsStore(storage: storage).load();
      expect(loaded.state, AppSettingsLoadState.migrated);
      expect(loaded.settings.visualStyle, AppVisualStyle.material);
      expect(loaded.settings.theme, AppThemePreference.dark);
    });
  });

  group('Settings visual style switcher', () {
    test(
      'search keywords find Appearance for editorial terms in en and zh',
      () {
        final en = lookupAppLocalizations(const Locale('en'));
        final zh = lookupAppLocalizations(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        );
        const editorialSettings = AppSettings(
          theme: AppThemePreference.light,
          visualStyle: AppVisualStyle.editorial,
        );

        expect(
          SettingsSection.appearance.matches(
            'editorial',
            editorialSettings,
            en,
          ),
          isTrue,
        );
        expect(
          SettingsSection.appearance.matches('magazine', editorialSettings, en),
          isTrue,
        );
        expect(
          SettingsSection.appearance.summary(editorialSettings, en),
          contains('Magazine Editorial'),
        );

        expect(
          SettingsSection.appearance.matches('杂志', editorialSettings, zh),
          isTrue,
        );
        expect(
          SettingsSection.appearance.matches('文艺', editorialSettings, zh),
          isTrue,
        );
        expect(
          SettingsSection.appearance.matches('衬线', editorialSettings, zh),
          isTrue,
        );
        expect(
          SettingsSection.appearance.summary(editorialSettings, zh),
          contains('杂志文艺'),
        );
      },
    );

    for (final language in ['en', 'zh']) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'switches live between Material 3 and Magazine Editorial ($language, $brightness)',
          (tester) async {
            tester.view.physicalSize = const Size(1200, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              _LiveSettingsHarness(language: language, brightness: brightness),
            );
            await tester.pumpAndSettle();

            final editorialCard = find.byKey(
              const ValueKey('settings-visual-style-editorial'),
            );
            final materialCard = find.byKey(
              const ValueKey('settings-visual-style-material'),
            );
            expect(editorialCard, findsOneWidget);
            expect(materialCard, findsOneWidget);
            expect(tester.element(editorialCard).isEditorialTheme, isFalse);

            await tester.ensureVisible(editorialCard);
            await tester.tap(editorialCard);
            await tester.pumpAndSettle();

            expect(tester.element(editorialCard).isEditorialTheme, isTrue);
            expect(
              Theme.of(tester.element(editorialCard)).scaffoldBackgroundColor,
              brightness == Brightness.dark
                  ? MusicEditorialTheme.editorialDark.paperCanvas
                  : MusicEditorialTheme.editorialLight.paperCanvas,
            );

            await tester.ensureVisible(materialCard);
            await tester.tap(materialCard);
            await tester.pumpAndSettle();

            expect(tester.element(materialCard).isEditorialTheme, isFalse);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'visual style switcher fits 320px compact viewport at 2.5x text scale without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final (language, expectedLabel) in [
          ('en', 'Magazine Editorial'),
          ('zh', '杂志文艺'),
        ]) {
          await tester.pumpWidget(
            _LiveSettingsHarness(
              language: language,
              brightness: Brightness.light,
              initialStyle: AppVisualStyle.editorial,
              compact: true,
              textScale: 2.5,
            ),
          );
          await tester.pumpAndSettle();

          final editorialCard = find.byKey(
            const ValueKey('settings-visual-style-editorial'),
          );
          await tester.scrollUntilVisible(
            editorialCard,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();

          expect(editorialCard, findsOneWidget);
          expect(find.text(expectedLabel), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('Editorial surface craft', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'LyricPanel renders large editorial serif lyrics without active highlight pill ($brightness)',
        (tester) async {
          final controller = LyricController(_StaticLyricGateway());
          addTearDown(controller.dispose);
          await controller.load(_sampleTrack);
          controller.updatePositionMs(1400);

          final theme = brightness == Brightness.dark
              ? MusicMaterialTheme.dark(visualStyle: AppVisualStyle.editorial)
              : MusicMaterialTheme.light(visualStyle: AppVisualStyle.editorial);
          final expectedTokens = brightness == Brightness.dark
              ? MusicEditorialTheme.editorialDark
              : MusicEditorialTheme.editorialLight;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: LyricPanel(
                  controller: controller,
                  immersive: true,
                  showCloseButton: false,
                  onClose: () {},
                  onSignInAgain: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final activeLine = find.byKey(const ValueKey('lyrics-line-0'));
          final inactiveLine = find.byKey(const ValueKey('lyrics-line-1'));
          expect(activeLine, findsOneWidget);
          expect(inactiveLine, findsOneWidget);

          final activeContainer = tester.widget<Container>(
            find
                .descendant(of: activeLine, matching: find.byType(Container))
                .first,
          );
          final activeDecoration = activeContainer.decoration! as BoxDecoration;
          expect(activeDecoration.color, Colors.transparent);

          final activeTextStyle = tester
              .widget<DefaultTextStyle>(
                find
                    .descendant(
                      of: activeLine,
                      matching: find.byType(DefaultTextStyle),
                    )
                    .first,
              )
              .style;
          final inactiveTextStyle = tester
              .widget<DefaultTextStyle>(
                find
                    .descendant(
                      of: inactiveLine,
                      matching: find.byType(DefaultTextStyle),
                    )
                    .first,
              )
              .style;

          expect(activeTextStyle.fontFamily, editorialSerifFontFamily);
          expect(activeTextStyle.fontSize, 27);
          expect(activeTextStyle.color, expectedTokens.inkPrimary);
          expect(inactiveTextStyle.color!.a, lessThan(0.4));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'ExpandedNowPlayingPage renders archival canvas, centered eyebrow, open lyrics, and gallery cover ($brightness)',
        (tester) async {
          for (final size in [const Size(1280, 820), const Size(390, 844)]) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final controller = _buildPlaybackController();
            addTearDown(controller.dispose);
            final theme = brightness == Brightness.dark
                ? MusicMaterialTheme.dark(visualStyle: AppVisualStyle.editorial)
                : MusicMaterialTheme.light(
                    visualStyle: AppVisualStyle.editorial,
                  );
            final expectedTokens = brightness == Brightness.dark
                ? MusicEditorialTheme.editorialDark
                : MusicEditorialTheme.editorialLight;

            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('zh'),
                theme: theme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ExpandedNowPlayingPage(
                  controller: controller,
                  onBack: () {},
                  onSignInAgain: () {},
                  artworkImageProviderBuilder: (_) => MemoryImage(_tinyPng),
                  artworkColorSchemeLoader:
                      ({required provider, required brightness}) async =>
                          ColorScheme.fromSeed(
                            seedColor: const Color(0xFF8E3B2E),
                            brightness: brightness,
                          ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('01. 正在播放'), findsOneWidget);
            final lyricsSurface = tester.widget<Material>(
              find.byKey(const ValueKey('expanded-now-playing-lyrics-surface')),
            );
            expect(lyricsSurface.type, MaterialType.transparency);

            final controls = tester.widget<Material>(
              find.byKey(const ValueKey('expanded-now-playing-controls')),
            );
            expect(controls.color, expectedTokens.paperCanvas);
            expect(controls.elevation, 0);

            final artworkFrame = tester.widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('expanded-now-playing-artwork'),
                    ),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            expect(artworkFrame.position, DecorationPosition.foreground);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }

    testWidgets(
      'Editorial collection header and track table render real Duration header without overflow and paint foreground artwork hairline',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final (locale, textScale) in [
          (const Locale('en'), 1.0),
          (const Locale('en'), 2.0),
          (const Locale('zh'), 2.0),
        ]) {
          final l10n = lookupAppLocalizations(locale);
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              theme: MusicMaterialTheme.light(
                visualStyle: AppVisualStyle.editorial,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: Column(
                  children: [
                    LibraryCollectionHeader(
                      title: 'My Collection',
                      subtitle: '5 pieces curated for quiet evenings',
                      refreshTooltip: 'Refresh',
                      onRefresh: () {},
                    ),
                    MusicTrackTableHeader(
                      titleLabel: l10n.tableTitle,
                      artistLabel: l10n.tableArtist,
                      albumLabel: l10n.tableAlbum,
                      durationLabel: l10n.tableDuration,
                    ),
                    MusicTrackRowSurface(
                      itemKey: const ValueKey('editorial-track-0'),
                      desktop: true,
                      current: true,
                      semanticLabel: 'Silver Air',
                      onTap: () {},
                      contentBuilder: (context, active, hovered) =>
                          MusicTrackRowContent(
                            index: 1,
                            track: _sampleTrack,
                            desktop: true,
                            current: true,
                            active: active,
                            artistNames: 'Fractured Glass',
                            onPlay: () {},
                            onAddToQueue: () {},
                            onMore: () {},
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('01'), findsOneWidget);
          expect(find.text('My Collection'), findsOneWidget);
          expect(find.text(l10n.tableTitle.toUpperCase()), findsOneWidget);
          expect(find.text(l10n.tableArtist.toUpperCase()), findsOneWidget);
          expect(find.text(l10n.tableAlbum.toUpperCase()), findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

          final trackArtworkFrame = tester.widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(MusicTrackArtwork),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(trackArtworkFrame.position, DecorationPosition.foreground);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'NowPlayingBar paints foreground top hairline border and artwork frame in Editorial mode',
      (tester) async {
        for (final brightness in Brightness.values) {
          for (final size in [const Size(1200, 800), const Size(390, 844)]) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final controller = _buildPlaybackController();
            addTearDown(controller.dispose);
            final theme = brightness == Brightness.dark
                ? MusicMaterialTheme.dark(visualStyle: AppVisualStyle.editorial)
                : MusicMaterialTheme.light(
                    visualStyle: AppVisualStyle.editorial,
                  );

            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  bottomNavigationBar: NowPlayingBar(
                    controller: controller,
                    onSignInAgain: () {},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final artworkFrame = tester.widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('now-playing-artwork')),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            expect(artworkFrame.position, DecorationPosition.foreground);

            if (size.width >= 900) {
              final barTopBorder = tester.widget<DecoratedBox>(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('now-playing-desktop-bar')),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              );
              expect(barTopBorder.position, DecorationPosition.foreground);
            }
            expect(tester.takeException(), isNull);
          }
        }
      },
    );

    testWidgets(
      'CollectionDetailHeader, RankingArtwork, and AdaptiveSideSheet use Editorial 4px framing and foreground hairlines',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tokens = MusicEditorialTheme.editorialLight;
        await tester.pumpWidget(
          MaterialApp(
            theme: MusicMaterialTheme.light(
              visualStyle: AppVisualStyle.editorial,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    MusicCollectionDetailHeader(
                      collapseProgress: 0,
                      desktop: true,
                      embedded: false,
                      artwork: const RankingArtwork(),
                      eyebrow: 'Chart',
                      title: 'Late Night Classics',
                      titleKey: const ValueKey('editorial-detail-title'),
                      summary: '12 recordings',
                      onBack: () {},
                      backKey: const ValueKey('editorial-detail-back'),
                      backTooltip: 'Back',
                    ),
                    FilledButton(
                      onPressed: () {
                        showAdaptiveSideSheet<void>(
                          context: context,
                          surfaceKey: const ValueKey('editorial-side-sheet'),
                          builder: (_) => const SizedBox.expand(),
                        );
                      },
                      child: const Text('Open Sheet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('01 · CHART'), findsOneWidget);
        final headerArtworkFrame = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byKey(const ValueKey('collection-detail-artwork')),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(headerArtworkFrame.position, DecorationPosition.foreground);

        final rankingClip = tester.widget<ClipRRect>(
          find
              .descendant(
                of: find.byType(RankingArtwork),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        expect(rankingClip.borderRadius, tokens.artworkRadius);

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        final sideSheet = tester.widget<Material>(
          find.byKey(const ValueKey('editorial-side-sheet')),
        );
        expect(sideSheet.color, tokens.paperCanvas);
        final sheetShape = sideSheet.shape! as RoundedRectangleBorder;
        expect(sheetShape.borderRadius, tokens.cardRadius);
        expect(sheetShape.side.color, tokens.hairline);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _LiveSettingsHarness extends StatefulWidget {
  const _LiveSettingsHarness({
    required this.language,
    required this.brightness,
    this.initialStyle = AppVisualStyle.material,
    this.compact = false,
    this.textScale = 1.0,
  });

  final String language;
  final Brightness brightness;
  final AppVisualStyle initialStyle;
  final bool compact;
  final double textScale;

  @override
  State<_LiveSettingsHarness> createState() => _LiveSettingsHarnessState();
}

class _LiveSettingsHarnessState extends State<_LiveSettingsHarness> {
  late AppSettings _settings = AppSettings.defaults.copyWith(
    visualStyle: widget.initialStyle,
  );

  @override
  Widget build(BuildContext context) {
    final theme = widget.brightness == Brightness.dark
        ? MusicMaterialTheme.dark(visualStyle: _settings.visualStyle)
        : MusicMaterialTheme.light(visualStyle: _settings.visualStyle);
    return MaterialApp(
      locale: Locale(widget.language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: child!,
      ),
      home: SettingsPage(
        settings: _settings,
        selectedSection: SettingsSection.appearance,
        compactHierarchy: widget.compact,
        compactSectionOpen: widget.compact,
        onBack: () {},
        onCompactSectionSelected: (_) {},
        onSettingsChanged: (next) async {
          setState(() => _settings = next);
          return AppSettingsWriteResult.saved;
        },
      ),
    );
  }
}

class _MemorySettingsStorage implements AppSettingsDocumentStorage {
  _MemorySettingsStorage({this.document});

  String? document;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String value) async {
    document = value;
  }

  @override
  Future<void> delete() async {
    document = null;
  }
}

const _sampleTrack = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track-editorial-1',
  title: 'Silver Air',
  artistNames: ['Fractured Glass'],
  albumTitle: 'Dawn EP',
  artworkUri: 'https://example.invalid/editorial-cover.png',
  durationSeconds: 320,
);

class _StaticLyricGateway implements LyricGateway {
  const _StaticLyricGateway();

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => const _ImmediateLyricOperation();
}

class _ImmediateLyricOperation implements LyricLoadOperation {
  const _ImmediateLyricOperation();

  @override
  bool cancel() => true;

  @override
  Future<LyricLoadResult> run() async => LyricLoadResult(
    lyrics: SynchronizedLyrics([
      SynchronizedLyricLine(
        startMs: 1000,
        durationMs: 3000,
        text: 'We breathe the silver air',
        translation: '我们呼吸着银色的空气',
        segments: const [
          TimedLyricSegment(
            startMs: 1000,
            durationMs: 1500,
            text: 'We breathe ',
          ),
          TimedLyricSegment(
            startMs: 2500,
            durationMs: 1500,
            text: 'the silver air',
          ),
        ],
      ),
      SynchronizedLyricLine(
        startMs: 4000,
        durationMs: 3000,
        text: 'And wait for the dawn to break.',
        segments: const [],
      ),
    ]),
  );
}

class _StubAudioEngine implements ForegroundAudioEngine {
  const _StubAudioEngine();

  @override
  Future<void> dispose() async {}

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) => throw StateError('unused in editorial theme widget test');
}

class _StubMediaGateway implements MediaResolutionGateway {
  const _StubMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _ImmediateMediaOp();
}

class _ImmediateMediaOp implements MediaResolutionOperation {
  const _ImmediateMediaOp();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async =>
      const MediaResolutionResult(failure: MediaResolutionFailure.unavailable);
}

class _StubQueueGateway implements PlaybackQueueGateway {
  final PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot(
    tracks: const [_sampleTrack],
    currentIndex: 0,
    hasPrevious: false,
    hasNext: false,
  );

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult advance() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult clear() =>
      PlaybackQueueResult(snapshot: PlaybackQueueSnapshot.empty());

  @override
  PlaybackQueueResult completeCurrent() =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult extendAndAdvanceFromTerminal(
    List<PlaylistTrackSummary> tracks,
  ) => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult remove(int index) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult rewind() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult select(int index) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) =>
      PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) =>
      PlaybackQueueResult(snapshot: _snapshot);
}

QueuePlaybackController _buildPlaybackController() {
  final lyrics = LyricController(const _StaticLyricGateway());
  return QueuePlaybackController(
    _StubQueueGateway(),
    TrackPlaybackController(
      const _StubMediaGateway(),
      ForegroundPlaybackController(const _StubAudioEngine()),
    ),
    lyrics: lyrics,
  );
}

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+8Z0AAAAASUVORK5CYII=',
);
