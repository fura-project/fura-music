use netease_client::{HttpsTransport, NeteaseClient};
use provider_netease::NeteaseProvider;
use std::sync::OnceLock;

pub(crate) type NativeNeteaseProvider = NeteaseProvider<HttpsTransport>;

const fn netease_refresh_activation_enabled() -> bool {
    false
}

fn build_native_netease_provider(client: NeteaseClient<HttpsTransport>) -> NativeNeteaseProvider {
    NeteaseProvider::new_with_refresh_activation(client, netease_refresh_activation_enabled())
}

/// One process-wide NetEase owner for every native Core route.
///
/// Authentication and media resolution must share this exact instance so a
/// credential can never be installed into a provider that playback bypasses.
pub(crate) fn native_netease_provider() -> Result<&'static NativeNeteaseProvider, ()> {
    static PROVIDER: OnceLock<Result<NativeNeteaseProvider, ()>> = OnceLock::new();
    match PROVIDER.get_or_init(|| {
        HttpsTransport::new()
            .map(NeteaseClient::new)
            .map(build_native_netease_provider)
            .map_err(|_| ())
    }) {
        Ok(provider) => Ok(provider),
        Err(()) => Err(()),
    }
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

    #[test]
    fn production_refresh_gate_remains_disabled_pending_human_evidence() {
        assert!(!netease_refresh_activation_enabled());
    }
}
