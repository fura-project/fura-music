/// Operating-system media integration boundary.
///
/// Implementations project one existing QueuePlaybackController and send every
/// received command back to it. They never own a source URI, player or Queue.
abstract interface class SystemMediaEdge {
  bool get isActive;

  Future<void> activate();
  Future<void> deactivate();
}
