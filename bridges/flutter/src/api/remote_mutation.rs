use std::sync::atomic::{AtomicBool, Ordering};

use tokio::sync::Notify;

pub(super) enum RemoteMutationStart {
    Started,
    Cancelled,
    AlreadyRunning,
}

/// Shared single-use lifecycle for remote writes. It deliberately does not
/// interpret operation inputs, results, or failure semantics.
pub(super) struct RemoteMutationLifecycle {
    active: AtomicBool,
    running: AtomicBool,
    cancelled: Notify,
}

impl RemoteMutationLifecycle {
    pub(super) const fn new() -> Self {
        Self {
            active: AtomicBool::new(true),
            running: AtomicBool::new(false),
            cancelled: Notify::const_new(),
        }
    }

    pub(super) fn try_start(&self) -> RemoteMutationStart {
        if !self.active.load(Ordering::SeqCst) {
            return RemoteMutationStart::Cancelled;
        }
        if self.running.swap(true, Ordering::SeqCst) {
            return RemoteMutationStart::AlreadyRunning;
        }
        RemoteMutationStart::Started
    }

    pub(super) async fn cancelled(&self) {
        self.cancelled.notified().await;
    }

    pub(super) fn finish(&self) {
        self.running.store(false, Ordering::SeqCst);
        self.active.store(false, Ordering::SeqCst);
    }

    pub(super) fn cancel(&self) -> bool {
        let was_active = self.active.swap(false, Ordering::SeqCst);
        if was_active {
            self.cancelled.notify_one();
        }
        was_active
    }

    pub(super) fn is_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }

    pub(super) fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::{RemoteMutationLifecycle, RemoteMutationStart};

    #[test]
    fn single_use_lifecycle_distinguishes_cancelled_and_running() {
        let cancelled = RemoteMutationLifecycle::new();
        assert!(cancelled.is_active());
        assert!(cancelled.cancel());
        assert!(!cancelled.cancel());
        assert!(matches!(
            cancelled.try_start(),
            RemoteMutationStart::Cancelled
        ));

        let running = RemoteMutationLifecycle::new();
        assert!(matches!(running.try_start(), RemoteMutationStart::Started));
        assert!(running.is_running());
        assert!(matches!(
            running.try_start(),
            RemoteMutationStart::AlreadyRunning
        ));
        running.finish();
        assert!(!running.is_active());
        assert!(!running.is_running());
    }

    #[tokio::test]
    async fn cancellation_notification_survives_before_waiter_registration() {
        let lifecycle = RemoteMutationLifecycle::new();
        assert!(lifecycle.cancel());
        lifecycle.cancelled().await;
    }
}
