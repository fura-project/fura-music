import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_section_selector.dart';
import 'package:flutterustmusic/navigation/authenticated_navigation_state.dart';

void main() {
  test('starts at Home and has no local Back target', () {
    final navigation = AuthenticatedNavigationState();

    expect(navigation.primaryDestination, AuthenticatedPrimaryDestination.home);
    expect(navigation.librarySection, LibrarySection.playlists);
    expect(navigation.routes, isEmpty);
    expect(navigation.canGoBack, isFalse);
    expect(navigation.goBack().target, AuthenticatedBackTarget.none);
  });

  test('records retained destination and Library-section visits', () {
    final navigation = AuthenticatedNavigationState();

    expect(
      navigation.selectPrimaryDestination(
        AuthenticatedPrimaryDestination.search,
      ),
      isTrue,
    );
    expect(
      navigation.visitedDestination(AuthenticatedPrimaryDestination.search),
      isTrue,
    );
    expect(navigation.goBack().target, AuthenticatedBackTarget.home);
    expect(
      navigation.selectPrimaryDestination(
        AuthenticatedPrimaryDestination.library,
      ),
      isTrue,
    );
    expect(navigation.selectLibrarySection(LibrarySection.albums), isTrue);
    expect(navigation.visitedLibrarySection(LibrarySection.albums), isTrue);

    expect(
      navigation.goBack().target,
      AuthenticatedBackTarget.libraryPlaylists,
    );
    expect(navigation.librarySection, LibrarySection.playlists);
    expect(navigation.goBack().target, AuthenticatedBackTarget.home);
  });

  test('Back pops exactly one typed local route before its destination', () {
    final navigation = AuthenticatedNavigationState();
    navigation.selectPrimaryDestination(
      AuthenticatedPrimaryDestination.discover,
    );
    const first = ExpandedNowPlayingLocalRoute();
    const second = ExpandedNowPlayingLocalRoute();
    navigation
      ..push(first)
      ..push(second);

    expect(navigation.routes, [same(first), same(second)]);
    expect(
      navigation.selectPrimaryDestination(
        AuthenticatedPrimaryDestination.library,
      ),
      isFalse,
    );

    final firstBack = navigation.goBack();
    expect(firstBack.target, AuthenticatedBackTarget.localRoute);
    expect(firstBack.route, same(second));
    expect(navigation.routes, [same(first)]);

    final secondBack = navigation.goBack();
    expect(secondBack.route, same(first));
    expect(navigation.goBack().target, AuthenticatedBackTarget.home);
  });
}
