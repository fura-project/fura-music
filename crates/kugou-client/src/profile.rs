//! Accepted anonymous public profile only. An authenticated profile is not
//! instantiated until install identity, signing and entitlement are accepted.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum KuGouProtocolProfile {
    Public,
}

impl KuGouProtocolProfile {
    pub(crate) const fn headers(self) -> [(&'static str, &'static str); 2] {
        match self {
            Self::Public => [
                ("Accept", "application/json,text/plain;q=0.9"),
                ("User-Agent", "fura-music/0.1"),
            ],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn public_headers_preserve_the_pre_extraction_wire_contract() {
        assert_eq!(
            KuGouProtocolProfile::Public.headers(),
            [
                ("Accept", "application/json,text/plain;q=0.9"),
                ("User-Agent", "fura-music/0.1"),
            ]
        );
    }
}
