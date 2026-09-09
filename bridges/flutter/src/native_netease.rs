use netease_client::{HttpsTransport, NeteaseClient};
use provider_netease::NeteaseProvider;
use std::sync::OnceLock;

pub(crate) type NativeNeteaseProvider = NeteaseProvider<HttpsTransport>;

/// One process-wide NetEase owner for every native Core route.
///
/// Authentication and media resolution must share this exact instance so a
/// credential can never be installed into a provider that playback bypasses.
pub(crate) fn native_netease_provider() -> Result<&'static NativeNeteaseProvider, ()> {
    static PROVIDER: OnceLock<Result<NativeNeteaseProvider, ()>> = OnceLock::new();
    PROVIDER
        .get_or_init(|| {
            HttpsTransport::new()
                .map(|transport| NeteaseProvider::new(NeteaseClient::new(transport)))
                .map_err(|_| ())
        })
        .as_ref()
        .map_err(|()| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_native_route_receives_the_same_provider_instance() {
        let first = native_netease_provider().expect("native HTTPS provider");
        let second = native_netease_provider().expect("native HTTPS provider");
        assert!(std::ptr::eq(first, second));
    }
}
