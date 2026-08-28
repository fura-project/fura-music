import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/home_controller.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';

void main() {
  test('keeps independent Home resources truthful when one fails', () async {
    final controller = HomeController(
      _AccountGateway(
        const AccountSummaryLoadResult(
          summary: AuthenticatedAccountSummary(displayName: 'Listener'),
        ),
      ),
      _DailyGateway(
        const DailyRecommendationResult(
          playlist: RecommendedPlaylistSummary(
            providerId: 'qq-music',
            opaqueId: 'daily:30',
            title: 'Daily 30',
          ),
        ),
      ),
      _PlaylistsGateway(const PersonalizedPlaylistsResult()),
      _TracksGateway(
        const PersonalizedTracksResult(
          failure: PersonalizedTracksFailure.network,
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.accountStage, HomeResourceStage.content);
    expect(controller.account?.displayName, 'Listener');
    expect(controller.dailyStage, HomeResourceStage.content);
    expect(controller.dailyPlaylist?.title, 'Daily 30');
    expect(controller.personalizedPlaylistsStage, HomeResourceStage.empty);
    expect(controller.personalizedTracksStage, HomeResourceStage.error);
    expect(
      controller.personalizedTracksFailure,
      PersonalizedTracksFailure.network,
    );
    expect(controller.requiresSignIn, isFalse);
  });

  test(
    'exposes credential rejection without discarding other content',
    () async {
      final controller = HomeController(
        _AccountGateway(
          const AccountSummaryLoadResult(
            summary: AuthenticatedAccountSummary(displayName: 'Listener'),
          ),
        ),
        _DailyGateway(
          const DailyRecommendationResult(
            failure: DailyRecommendationFailure.credentialRejected,
          ),
        ),
        _PlaylistsGateway(
          const PersonalizedPlaylistsResult(
            playlists: [
              RecommendedPlaylistSummary(
                providerId: 'qq-music',
                opaqueId: 'personal:1',
                title: 'Personal mix',
              ),
            ],
          ),
        ),
        _TracksGateway(const PersonalizedTracksResult()),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.requiresSignIn, isTrue);
      expect(controller.dailyStage, HomeResourceStage.error);
      expect(controller.personalizedPlaylistsStage, HomeResourceStage.content);
      expect(controller.personalizedPlaylists.single.title, 'Personal mix');
    },
  );

  test('retry reloads only the requested Home resource', () async {
    final daily = _DailyGateway(
      const DailyRecommendationResult(
        failure: DailyRecommendationFailure.network,
      ),
    );
    final account = _AccountGateway(
      const AccountSummaryLoadResult(
        summary: AuthenticatedAccountSummary(displayName: 'Listener'),
      ),
    );
    final playlists = _PlaylistsGateway(const PersonalizedPlaylistsResult());
    final tracks = _TracksGateway(const PersonalizedTracksResult());
    final controller = HomeController(account, daily, playlists, tracks);
    addTearDown(controller.dispose);

    await controller.load();
    daily.result = const DailyRecommendationResult(
      playlist: RecommendedPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'daily:30',
        title: 'Daily 30',
      ),
    );
    controller.retryDaily();
    await Future<void>.delayed(Duration.zero);

    expect(daily.beginCalls, 2);
    expect(account.beginCalls, 1);
    expect(playlists.beginCalls, 1);
    expect(tracks.beginCalls, 1);
    expect(controller.dailyStage, HomeResourceStage.content);
  });

  test('dispose cancels Home work and suppresses its late result', () async {
    final daily = _ControlledDailyGateway();
    final controller = HomeController(
      _AccountGateway(
        const AccountSummaryLoadResult(
          summary: AuthenticatedAccountSummary(displayName: 'Listener'),
        ),
      ),
      daily,
      _PlaylistsGateway(const PersonalizedPlaylistsResult()),
      _TracksGateway(const PersonalizedTracksResult()),
    );

    final load = controller.load();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    expect(daily.operation.cancelCalls, 1);

    daily.operation.complete(
      const DailyRecommendationResult(
        playlist: RecommendedPlaylistSummary(
          providerId: 'qq-music',
          opaqueId: 'daily:late',
          title: 'Late Daily 30',
        ),
      ),
    );
    await load;

    expect(controller.dailyPlaylist, isNull);
    expect(controller.dailyStage, HomeResourceStage.loading);
  });
}

class _AccountGateway implements AccountSummaryGateway {
  _AccountGateway(this.result);

  AccountSummaryLoadResult result;
  int beginCalls = 0;

  @override
  AccountSummaryLoadOperation beginLoad() {
    beginCalls++;
    return _AccountOperation(result);
  }
}

class _AccountOperation implements AccountSummaryLoadOperation {
  const _AccountOperation(this.result);

  final AccountSummaryLoadResult result;

  @override
  bool cancel() => true;

  @override
  Future<AccountSummaryLoadResult> run() async => result;
}

class _DailyGateway implements DailyRecommendationGateway {
  _DailyGateway(this.result);

  DailyRecommendationResult result;
  int beginCalls = 0;

  @override
  DailyRecommendationLoadOperation beginLoad() {
    beginCalls++;
    return _DailyOperation(result);
  }
}

class _DailyOperation implements DailyRecommendationLoadOperation {
  const _DailyOperation(this.result);

  final DailyRecommendationResult result;

  @override
  bool cancel() => true;

  @override
  Future<DailyRecommendationResult> run() async => result;
}

class _ControlledDailyGateway implements DailyRecommendationGateway {
  final _ControlledDailyOperation operation = _ControlledDailyOperation();

  @override
  DailyRecommendationLoadOperation beginLoad() => operation;
}

class _ControlledDailyOperation implements DailyRecommendationLoadOperation {
  final Completer<DailyRecommendationResult> _result = Completer();
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls++;
    return true;
  }

  void complete(DailyRecommendationResult result) => _result.complete(result);

  @override
  Future<DailyRecommendationResult> run() => _result.future;
}

class _PlaylistsGateway implements PersonalizedPlaylistsGateway {
  _PlaylistsGateway(this.result);

  PersonalizedPlaylistsResult result;
  int beginCalls = 0;

  @override
  PersonalizedPlaylistsLoadOperation beginLoad() {
    beginCalls++;
    return _PlaylistsOperation(result);
  }
}

class _PlaylistsOperation implements PersonalizedPlaylistsLoadOperation {
  const _PlaylistsOperation(this.result);

  final PersonalizedPlaylistsResult result;

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedPlaylistsResult> run() async => result;
}

class _TracksGateway implements PersonalizedTracksGateway {
  _TracksGateway(this.result);

  PersonalizedTracksResult result;
  int beginCalls = 0;

  @override
  PersonalizedTracksLoadOperation beginLoad() {
    beginCalls++;
    return _TracksOperation(result);
  }
}

class _TracksOperation implements PersonalizedTracksLoadOperation {
  const _TracksOperation(this.result);

  final PersonalizedTracksResult result;

  @override
  bool cancel() => true;

  @override
  Future<PersonalizedTracksResult> run() async => result;
}
