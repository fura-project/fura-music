import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/library/music_track_row.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/l10n/app_locale.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_page.dart';

import '../support/test_playback_queue_gateway.dart';

final AppLocalizations _en = lookupAppLocalizations(englishAppLocale);

Future<void> _selectSearchType(WidgetTester tester, String type) async {
  await tester.tap(find.byKey(const ValueKey('search-types')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('search-type-$type')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all Search types use the shared compact idle state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: _ResultSearchGateway(const TrackSearchPageResult()),
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    for (final (type, panelKey) in [
      ('tracks', 'track-search-idle'),
      ('artists', 'artist-search-idle'),
      ('albums', 'album-search-idle'),
      ('playlists', 'playlist-search-idle'),
    ]) {
      if (type != 'tracks') await _selectSearchType(tester, type);
      expect(find.byKey(ValueKey(panelKey)), findsOneWidget);
      expect(find.byType(MusicContentStatePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compact Track Search labels loading and reaches shared empty', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final search = _ControlledSearchGateway();
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: search,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'nothing here',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(find.byKey(const ValueKey('track-search-loading')), findsOneWidget);
    expect(find.byType(MusicLoadingPanel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('track-search-loading')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  _en.searchLoadingTracks(_en.providerQqMusic),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    search.complete(const TrackSearchPageResult(page: 1, total: 0, items: []));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('track-search-empty')), findsOneWidget);
    expect(find.text(_en.searchNoTracksTitle), findsOneWidget);
    expect(find.text('Edit search'), findsOneWidget);
    expect(find.byType(MusicContentStatePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Track Search failure has one live region and both actions', (
    tester,
  ) async {
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    final search = _ResultSearchGateway(
      const TrackSearchPageResult(failure: SearchFailure.network),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: search,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'network failure',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('track-search-error')), findsOneWidget);
    expect(find.text('Couldn’t search QQ Music'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Edit search'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated failure does not duplicate an outgoing Search body', (
    tester,
  ) async {
    final search = _SequentialControlledSearchGateway();
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: search,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    final field = find.byKey(const ValueKey('track-search-field'));
    await tester.enterText(field, 'first failure');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    search.completeNext(
      const TrackSearchPageResult(failure: SearchFailure.network),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('track-search-error')), findsOneWidget);

    await tester.enterText(field, 'second failure');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('track-search-loading')), findsOneWidget);
    search.completeNext(
      const TrackSearchPageResult(failure: SearchFailure.network),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(field, 'third failure');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('track-search-loading')), findsOneWidget);
    search.completeNext(
      const TrackSearchPageResult(failure: SearchFailure.network),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('track-search-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search result can be queued or handed to playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:searchMid:-',
      title: 'Search result',
      artistNames: ['Search artist'],
      albumTitle: 'Search album',
      durationSeconds: 180,
    );
    final search = _SearchGateway(track);
    final queue = TestPlaybackQueueGateway();
    final playback = QueuePlaybackController(
      queue,
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    ArtistSummary? openedArtist;

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: search,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (artist) => openedArtist = artist,
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      '  search words  ',
    );
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(search.requests, [('search words', 1, 30)]);
    expect(find.text('Search result'), findsOneWidget);
    expect(find.text('Search artist'), findsOneWidget);
    expect(find.text('Search album'), findsOneWidget);
    expect(find.text(_en.searchResultCount(1, 'search words')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TrackSearchPage),
        matching: find.byKey(const ValueKey('locate-current-track')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('track-search-more-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-artist-0-1')));
    await tester.pumpAndSettle();
    expect(openedArtist?.name, 'Second artist');

    await tester.tap(find.byKey(const ValueKey('track-search-more-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('track-search-add-to-queue-0')));
    await tester.pumpAndSettle();
    expect(queue.pushedTracks, [track]);
    expect(find.text('Added to queue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('track-search-result-0')));
    await tester.pumpAndSettle();
    expect(queue.replacedTracks, [track]);
    expect(queue.replacedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps valid Track Search rows beside a partial-result notice', (
    tester,
  ) async {
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:partial-search',
      title: 'Visible partial search track',
      artistNames: ['Visible artist'],
    );
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: const _ResultSearchGateway(
            TrackSearchPageResult(
              page: 1,
              total: 2,
              omittedItemCount: 1,
              items: [TrackSearchItem(track: track)],
            ),
          ),
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      'partial',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Visible partial search track'), findsOneWidget);
    expect(find.textContaining('1 unsafe item was skipped'), findsOneWidget);
    expect(find.byKey(const ValueKey('track-search-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing overlays debounced provider-backed suggestions', (
    tester,
  ) async {
    await _loadSearchReviewFonts(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const resultTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:search-result',
      title: 'Selected result',
      artistNames: ['Result artist'],
    );
    const suggestionTrack = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:search-suggestion',
      title: 'Nevada',
      artistNames: ['Vicetone', 'Cozi Zuehlsdorff'],
    );
    final search = _SearchGateway(resultTrack);
    final suggestions = _RecordingSearchGateway(
      const TrackSearchPageResult(
        page: 1,
        total: 1,
        items: [TrackSearchItem(track: suggestionTrack)],
      ),
    );
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TrackSearchPage(
          gateway: search,
          suggestionGateway: suggestions,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    final field = find.byKey(const ValueKey('track-search-field'));
    final selectorTop = tester.getTopLeft(
      find.byKey(const ValueKey('search-types')),
    );
    await tester.enterText(field, 'nev');
    await tester.pump(const Duration(milliseconds: 319));
    expect(suggestions.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(suggestions.requests, [('nev', 1, 8)]);
    expect(
      find.byKey(const ValueKey('track-search-suggestions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('track-search-suggestion-raw')),
      findsOneWidget,
    );
    expect(find.text('Search “nev”'), findsOneWidget);
    expect(find.text('Nevada'), findsOneWidget);
    expect(find.text('Vicetone · Cozi Zuehlsdorff'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('track-search-suggestions')))
          .width,
      closeTo(tester.getSize(field).width, 1),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('search-types'))),
      selectorTop,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('track-search-suggestion-0'))),
    );
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('track-search-suggestion-0')),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );
    if (const bool.fromEnvironment('SEARCH_VISUAL_REVIEW')) {
      for (final size in const [
        Size(1440, 900),
        Size(900, 700),
        Size(390, 844),
        Size(320, 700),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.tap(field);
        await tester.enterText(field, 'ne');
        await tester.enterText(field, 'nev');
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('track-search-suggestions')),
          findsOneWidget,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file(
              '/tmp/fura-search-suggestions-'
              '${size.width.toInt()}x${size.height.toInt()}.png',
            ),
          ),
        );
      }
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.enterText(field, 'ne');
      await tester.enterText(field, 'nev');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
    }

    await tester.tap(find.byKey(const ValueKey('track-search-suggestion-0')));
    await tester.pumpAndSettle();

    expect(search.requests, [('Nevada', 1, 30)]);
    expect(tester.widget<TextField>(field).controller?.text, 'Nevada');
    expect(
      find.byKey(const ValueKey('track-search-suggestions')),
      findsNothing,
    );
    expect(find.text('Selected result'), findsOneWidget);
    final resultTop = tester.getTopLeft(
      find.byKey(const ValueKey('track-search-result-0')),
    );
    await tester.tap(field);
    await tester.enterText(field, 'another query');
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('track-search-suggestions')),
      findsOneWidget,
    );
    expect(find.text('Selected result'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('track-search-result-0'))),
      resultTop,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'suggestion keyboard navigation keeps focus and rejects replaced entries',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const resultTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:keyboard-result',
        title: 'Keyboard result',
        artistNames: ['Keyboard artist'],
      );
      const suggestionTrack = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track:keyboard-suggestion',
        title: 'Keyboard suggestion',
        artistNames: ['Suggestion artist'],
      );
      final search = _SearchGateway(resultTrack);
      final suggestions = _RecordingSearchGateway(
        const TrackSearchPageResult(
          page: 1,
          total: 1,
          items: [TrackSearchItem(track: suggestionTrack)],
        ),
      );
      final playback = QueuePlaybackController(
        TestPlaybackQueueGateway(),
        TrackPlaybackController(
          const _UnavailableMediaGateway(),
          ForegroundPlaybackController(const _NeverAudioEngine()),
        ),
      );
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: TrackSearchPage(
            gateway: search,
            suggestionGateway: suggestions,
            queuePlaybackController: playback,
            onBack: () {},
            onOpenAlbum: (_) {},
            onOpenArtist: (_) {},
            onOpenPlaylist: (_) {},
            onSignInAgain: () {},
          ),
        ),
      );
      final field = find.byKey(const ValueKey('track-search-field'));
      await tester.enterText(field, 'key');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
      final fieldFocus = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(fieldFocus));
      expect(
        tester
            .widget<Semantics>(
              find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('track-search-suggestion-raw'),
                    ),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester
            .widget<Semantics>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('track-search-suggestion-0')),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.enterText(field, 'replacement');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('track-search-suggestion-0')),
        findsNothing,
      );
      expect(find.text('Search “replacement”'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(
              find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('track-search-suggestion-raw'),
                    ),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('track-search-suggestions')),
        findsNothing,
      );
      expect(FocusManager.instance.primaryFocus, same(fieldFocus));

      await tester.enterText(field, 'outside');
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('track-search-suggestions')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(980, 680));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('track-search-suggestions')),
        findsNothing,
      );
      await tester.enterText(field, 'raw enter');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(search.requests.last, ('raw enter', 1, 30));

      await tester.enterText(field, 'key again');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(search.requests.last, ('Keyboard suggestion', 1, 30));
      expect(
        tester.widget<TextField>(field).controller?.text,
        'Keyboard suggestion',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact suggestions localize the raw action in Chinese', (
    tester,
  ) async {
    await _loadSearchReviewFonts(tester);
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TrackSearchPage(
          gateway: const _ResultSearchGateway(TrackSearchPageResult()),
          suggestionGateway: const _ResultSearchGateway(
            TrackSearchPageResult(),
          ),
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('track-search-field')),
      '神曼波',
    );
    await tester.pump();
    await tester.pump();

    final raw = find.byKey(const ValueKey('track-search-suggestion-raw'));
    expect(find.text('搜索“神曼波”'), findsOneWidget);
    expect(tester.getSize(raw).height, 48);
    expect(find.semantics.byLabel('搜索“神曼波”'), findsOne);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('SEARCH_VISUAL_REVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          Uri.file('/tmp/fura-search-suggestions-zh-390x844.png'),
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('desktop Track results use the common music table structure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:desktop-table',
      title: 'Desktop table result',
      artistNames: ['Desktop artist'],
      albumTitle: 'Desktop album',
      durationSeconds: 204,
    );
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: _SearchGateway(track),
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );
    final field = find.byKey(const ValueKey('track-search-field'));
    await tester.enterText(field, 'desktop query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byType(MusicTrackTableHeader), findsOneWidget);
    expect(find.byType(MusicTrackRowSurface), findsOneWidget);
    expect(find.text('Desktop artist'), findsOneWidget);
    expect(find.text('Desktop album'), findsOneWidget);
    expect(find.text('3:24'), findsOneWidget);
    expect(find.byKey(const ValueKey('track-search-more-0')), findsNothing);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('SEARCH_VISUAL_REVIEW')) {
      await expectLater(
        find.byType(TrackSearchPage),
        matchesGoldenFile(
          Uri.file('/tmp/flutterustmusic-search-desktop-results.png'),
        ),
      );
    }
  });

  testWidgets('Tracks, Artists, and Albums preserve independent Search state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:searchMid:-',
      title: 'Track result',
      artistNames: ['Track credit'],
    );
    final trackSearch = _SearchGateway(track);
    final artistSearch = _ArtistSearchGateway();
    final albumSearch = _AlbumSearchGateway();
    final playback = QueuePlaybackController(
      TestPlaybackQueueGateway(),
      TrackPlaybackController(
        const _UnavailableMediaGateway(),
        ForegroundPlaybackController(const _NeverAudioEngine()),
      ),
    );
    addTearDown(playback.dispose);
    ArtistSummary? openedArtist;
    AlbumSummary? openedAlbum;

    await tester.pumpWidget(
      MaterialApp(
        home: TrackSearchPage(
          gateway: trackSearch,
          artistGateway: artistSearch,
          albumGateway: albumSearch,
          queuePlaybackController: playback,
          onBack: () {},
          onOpenAlbum: (album) => openedAlbum = album,
          onOpenArtist: (artist) => openedArtist = artist,
          onOpenPlaylist: (_) {},
          onSignInAgain: () {},
        ),
      ),
    );

    final field = find.byKey(const ValueKey('track-search-field'));
    await tester.enterText(field, 'track query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Track result'), findsOneWidget);

    await _selectSearchType(tester, 'artists');
    expect(artistSearch.requests, [('track query', 1, 30)]);
    expect(find.text('Artist for track query'), findsOneWidget);

    await tester.enterText(field, 'artist query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(artistSearch.requests.last, ('artist query', 1, 30));
    expect(find.text('Artist for artist query'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artist-search-result-0')));
    await tester.pumpAndSettle();
    expect(openedArtist?.name, 'Artist for artist query');

    await _selectSearchType(tester, 'albums');
    expect(albumSearch.requests, [('artist query', 1, 30)]);
    expect(find.text('Album for artist query'), findsOneWidget);

    await tester.enterText(field, 'album query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(albumSearch.requests.last, ('album query', 1, 30));
    expect(find.text('Album for album query'), findsOneWidget);

    await _selectSearchType(tester, 'tracks');
    expect(tester.widget<TextField>(field).controller?.text, 'track query');
    expect(find.text('Track result'), findsOneWidget);

    await _selectSearchType(tester, 'artists');
    expect(tester.widget<TextField>(field).controller?.text, 'artist query');
    expect(artistSearch.requests.length, 2);

    await _selectSearchType(tester, 'albums');
    expect(tester.widget<TextField>(field).controller?.text, 'album query');
    expect(albumSearch.requests.length, 2);
    await tester.tap(find.byKey(const ValueKey('album-search-result-0')));
    await tester.pumpAndSettle();
    expect(openedAlbum?.title, 'Album for album query');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _loadSearchReviewFonts(WidgetTester tester) async {
  const capture = bool.fromEnvironment('SEARCH_VISUAL_REVIEW');
  const reviewFont = String.fromEnvironment('HOME_REVIEW_CJK_FONT');
  if (!capture || reviewFont.isEmpty) return;
  await tester.runAsync(() async {
    await (FontLoader('Roboto')
          ..addFont(File(reviewFont).readAsBytes().then(ByteData.sublistView)))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
}

class _SearchGateway implements TrackSearchGateway {
  _SearchGateway(this.track);

  final PlaylistTrackSummary track;
  final List<(String, int, int)> requests = [];

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _SearchOperation(
      TrackSearchPageResult(
        page: page,
        total: 1,
        items: [
          TrackSearchItem(
            track: track,
            artists: const [
              ArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:61001:firstArtistMid',
                name: 'First artist',
              ),
              ArtistSummary(
                providerId: 'qq-music',
                opaqueId: 'artist:61002:secondArtistMid',
                name: 'Second artist',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchOperation implements TrackSearchPageLoadOperation {
  const _SearchOperation(this.result);

  final TrackSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<TrackSearchPageResult> run() async => result;
}

class _ResultSearchGateway implements TrackSearchGateway {
  const _ResultSearchGateway(this.result);

  final TrackSearchPageResult result;

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _SearchOperation(result);
}

class _RecordingSearchGateway implements TrackSearchGateway {
  _RecordingSearchGateway(this.result);

  final TrackSearchPageResult result;
  final List<(String, int, int)> requests = [];

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _SearchOperation(result);
  }
}

class _ControlledSearchGateway implements TrackSearchGateway {
  final Completer<TrackSearchPageResult> _completer = Completer();

  void complete(TrackSearchPageResult result) => _completer.complete(result);

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) => _FutureSearchOperation(_completer.future);
}

class _SequentialControlledSearchGateway implements TrackSearchGateway {
  final List<Completer<TrackSearchPageResult>> _operations = [];
  int _completionIndex = 0;

  void completeNext(TrackSearchPageResult result) {
    _operations[_completionIndex++].complete(result);
  }

  @override
  TrackSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    final completer = Completer<TrackSearchPageResult>();
    _operations.add(completer);
    return _FutureSearchOperation(completer.future);
  }
}

class _FutureSearchOperation implements TrackSearchPageLoadOperation {
  const _FutureSearchOperation(this.result);

  final Future<TrackSearchPageResult> result;

  @override
  bool cancel() => true;

  @override
  Future<TrackSearchPageResult> run() => result;
}

class _ArtistSearchGateway implements ArtistSearchGateway {
  final List<(String, int, int)> requests = [];

  @override
  ArtistSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _ArtistSearchOperation(
      ArtistSearchPageResult(
        page: page,
        total: 1,
        artists: [
          ArtistSummary(
            providerId: 'qq-music',
            opaqueId: 'artist:61001:fixtureArtistMid',
            name: 'Artist for $query',
          ),
        ],
      ),
    );
  }
}

class _ArtistSearchOperation implements ArtistSearchPageLoadOperation {
  const _ArtistSearchOperation(this.result);

  final ArtistSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<ArtistSearchPageResult> run() async => result;
}

class _AlbumSearchGateway implements AlbumSearchGateway {
  final List<(String, int, int)> requests = [];

  @override
  AlbumSearchPageLoadOperation beginLoad({
    required String query,
    required int page,
    required int size,
  }) {
    requests.add((query, page, size));
    return _AlbumSearchOperation(
      AlbumSearchPageResult(
        page: page,
        total: 1,
        albums: [
          AlbumSummary(
            providerId: 'qq-music',
            opaqueId: 'album:43001:fixtureAlbumMid',
            title: 'Album for $query',
          ),
        ],
      ),
    );
  }
}

class _AlbumSearchOperation implements AlbumSearchPageLoadOperation {
  const _AlbumSearchOperation(this.result);

  final AlbumSearchPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<AlbumSearchPageResult> run() async => result;
}

class _UnavailableMediaGateway implements MediaResolutionGateway {
  const _UnavailableMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => const _UnavailableMediaOperation();
}

class _UnavailableMediaOperation implements MediaResolutionOperation {
  const _UnavailableMediaOperation();

  @override
  bool cancel() => true;

  @override
  Future<MediaResolutionResult> run() async =>
      const MediaResolutionResult(failure: MediaResolutionFailure.unavailable);
}

class _NeverAudioEngine implements ForegroundAudioEngine {
  const _NeverAudioEngine();

  @override
  Future<ForegroundAudioSession> loadRemote(
    Uri source, {
    ForegroundAudioFormat format = ForegroundAudioFormat.mp3,
  }) => throw StateError('audio should not load for an unavailable source');
}
