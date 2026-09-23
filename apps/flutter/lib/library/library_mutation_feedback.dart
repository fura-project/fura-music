import 'package:flutter/material.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/l10n/app_localizations_context.dart';

typedef LibraryMutationFeedbackHandler = void Function(
  LibraryMutationStatus status,
);

/// Lets the authenticated shell place mutation feedback around persistent UI.
///
/// Standalone component tests and pages without a shell owner retain the
/// standard Material [SnackBar] fallback.
class LibraryMutationFeedbackScope extends InheritedWidget {
  const LibraryMutationFeedbackScope({
    required this.onStatus,
    required super.child,
    super.key,
  });

  final LibraryMutationFeedbackHandler onStatus;

  static LibraryMutationFeedbackHandler? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LibraryMutationFeedbackScope>()
          ?.onStatus;

  @override
  bool updateShouldNotify(LibraryMutationFeedbackScope oldWidget) =>
      onStatus != oldWidget.onStatus;
}

void showLibraryMutationFeedback(
  BuildContext context,
  LibraryMutationStatus status,
) {
  final handler = LibraryMutationFeedbackScope.maybeOf(context);
  if (handler != null) {
    handler(status);
    return;
  }
  final message = switch (status) {
    LibraryMutationStatus.confirmed => context.l10n.libraryMutationSuccess,
    LibraryMutationStatus.outcomeUnknown =>
      context.l10n.libraryMutationOutcomeUnknown,
    LibraryMutationStatus.alreadyRunning => context.l10n.libraryMutationPending,
    LibraryMutationStatus.definitiveFailure ||
    LibraryMutationStatus.unavailable => context.l10n.libraryMutationFailure,
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
