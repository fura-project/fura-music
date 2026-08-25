//! Raw QQ Music protocol boundary.
//!
//! Endpoint-specific requests and response models are added only with protocol
//! evidence. This initial seam owns transport without choosing an HTTP package.

/// A QQ Music protocol client parameterized by its transport implementation.
#[derive(Debug)]
pub struct QqMusicClient<T> {
    transport: T,
}

impl<T> QqMusicClient<T> {
    #[must_use]
    pub const fn new(transport: T) -> Self {
        Self { transport }
    }

    #[must_use]
    pub const fn transport(&self) -> &T {
        &self.transport
    }

    #[must_use]
    pub fn into_transport(self) -> T {
        self.transport
    }
}

#[cfg(test)]
mod tests {
    use super::QqMusicClient;

    #[test]
    fn client_owns_but_does_not_hide_transport_lifecycle() {
        let client = QqMusicClient::new("offline-transport");
        assert_eq!(client.transport(), &"offline-transport");
        assert_eq!(client.into_transport(), "offline-transport");
    }
}
