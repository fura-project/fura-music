//! Bounded, anonymous `KuGou` public HTTPS protocol.
//!
//! This crate is an independent implementation. It neither starts nor embeds
//! a third-party API server and it owns no cross-Provider identity or fallback.

mod search;
mod transport;

pub use search::{Album, Artist, SearchPage, SearchTrack};
pub use transport::{HttpsTransport, MAX_RESPONSE_BYTES, Request, Response, Transport};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Error {
    RateLimited,
    SecurityVerificationRequired,
    ProtocolUnavailable,
    TemporaryNetworkFailure,
    UpstreamUnknown,
    InputBound,
    ResponseBound,
    ResponseShapeMismatch,
}

impl std::fmt::Display for Error {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "KuGou {self:?}")
    }
}

impl std::error::Error for Error {}

pub struct KuGouClient<T> {
    transport: T,
}

impl<T> KuGouClient<T> {
    #[must_use]
    pub const fn new(transport: T) -> Self {
        Self { transport }
    }
}
