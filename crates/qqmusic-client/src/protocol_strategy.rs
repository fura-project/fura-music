//! Small policy vocabulary for capability-local QQ protocol routing.
//!
//! This module deliberately does not own a registry or execute requests. Each
//! capability keeps its concrete request builder and decoder. The shared types
//! only make authentication selection and fallback/stop semantics explicit.

use crate::Credential;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[allow(
    dead_code,
    reason = "the evidence policy records auth modes before every capability needs alternate routes"
)]
pub(crate) enum QqCapabilityAuthPolicy {
    AnonymousOnly,
    AuthenticatedPreferred,
    AuthenticatedRequired,
}

impl QqCapabilityAuthPolicy {
    #[allow(
        dead_code,
        reason = "capability-local routes adopt this selector only when they have more than one auth path"
    )]
    pub(crate) fn select_credential(
        self,
        credential: Option<&Credential>,
    ) -> Result<Option<&Credential>, QqProtocolOutcome> {
        match self {
            Self::AnonymousOnly => Ok(None),
            Self::AuthenticatedPreferred => Ok(credential),
            Self::AuthenticatedRequired => credential
                .map(Some)
                .ok_or(QqProtocolOutcome::AuthenticationRequired),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[allow(
    dead_code,
    reason = "the authorized outcome taxonomy is intentionally broader than today's production routes"
)]
pub(crate) enum QqProtocolOutcome {
    Success,
    ValidEmpty,
    AuthenticationRequired,
    ProtocolUnavailable,
    EndpointUnavailable,
    UnsupportedByStrategy,
    ResponseShapeMismatch,
    IncompleteData,
    TemporaryNetworkFailure,
    RateLimited,
    SecurityVerificationRequired,
    CredentialRejected,
    AccountRestricted,
    DeviceRestricted,
    VipRequired,
    EntitlementDenied,
    CopyrightRestricted,
    RegionRestricted,
    UpstreamUnknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum QqStrategyDecision {
    Return,
    TryNext,
    RetryBoundedly,
    Stop,
}

impl QqProtocolOutcome {
    pub(crate) const fn decision(self) -> QqStrategyDecision {
        match self {
            Self::Success | Self::ValidEmpty => QqStrategyDecision::Return,
            Self::ProtocolUnavailable
            | Self::EndpointUnavailable
            | Self::UnsupportedByStrategy
            | Self::ResponseShapeMismatch
            | Self::IncompleteData => QqStrategyDecision::TryNext,
            Self::TemporaryNetworkFailure => QqStrategyDecision::RetryBoundedly,
            Self::AuthenticationRequired
            | Self::RateLimited
            | Self::SecurityVerificationRequired
            | Self::CredentialRejected
            | Self::AccountRestricted
            | Self::DeviceRestricted
            | Self::VipRequired
            | Self::EntitlementDenied
            | Self::CopyrightRestricted
            | Self::RegionRestricted
            | Self::UpstreamUnknown => QqStrategyDecision::Stop,
        }
    }
}

/// Classifies the bounded evidence currently shared by QQ musicu operations.
///
/// Code `2001` has independent repository evidence as a session-level
/// rate-limit response. Other non-zero codes remain unknown and therefore stop
/// instead of being guessed into authentication, content availability, or a
/// fallback-safe category.
pub(crate) fn classify_musicu_codes(
    global_code: i64,
    result_code: Option<i64>,
) -> Result<(), QqProtocolOutcome> {
    let outcome = if is_musicu_rate_limited_code(global_code)
        || result_code.is_some_and(is_musicu_rate_limited_code)
    {
        QqProtocolOutcome::RateLimited
    } else if global_code == 0 && !matches!(result_code, Some(code) if code != 0) {
        QqProtocolOutcome::Success
    } else {
        QqProtocolOutcome::UpstreamUnknown
    };
    match outcome.decision() {
        QqStrategyDecision::Return => Ok(()),
        QqStrategyDecision::Stop => Err(outcome),
        QqStrategyDecision::TryNext | QqStrategyDecision::RetryBoundedly => {
            unreachable!("musicu status codes do not permit retry or fallback")
        }
    }
}

pub(crate) const fn is_musicu_rate_limited_code(code: i64) -> bool {
    code == 2001
}

#[cfg(test)]
mod tests {
    use super::{
        QqCapabilityAuthPolicy, QqProtocolOutcome, QqStrategyDecision, classify_musicu_codes,
    };
    use crate::{Credential, LoginType};

    fn credential() -> Credential {
        Credential::new("123456", "W_X_private-key", LoginType::WECHAT).expect("credential")
    }

    #[test]
    fn auth_policy_selects_only_the_authorized_request_context() {
        let credential = credential();
        assert_eq!(
            QqCapabilityAuthPolicy::AnonymousOnly.select_credential(None),
            Ok(None)
        );
        assert_eq!(
            QqCapabilityAuthPolicy::AnonymousOnly.select_credential(Some(&credential)),
            Ok(None)
        );
        assert_eq!(
            QqCapabilityAuthPolicy::AuthenticatedPreferred.select_credential(None),
            Ok(None)
        );
        assert_eq!(
            QqCapabilityAuthPolicy::AuthenticatedPreferred.select_credential(Some(&credential)),
            Ok(Some(&credential))
        );
        assert_eq!(
            QqCapabilityAuthPolicy::AuthenticatedRequired.select_credential(None),
            Err(QqProtocolOutcome::AuthenticationRequired)
        );
        assert_eq!(
            QqCapabilityAuthPolicy::AuthenticatedRequired.select_credential(Some(&credential)),
            Ok(Some(&credential))
        );
    }

    #[test]
    fn only_protocol_compatibility_outcomes_try_the_next_known_strategy() {
        for outcome in [
            QqProtocolOutcome::ProtocolUnavailable,
            QqProtocolOutcome::EndpointUnavailable,
            QqProtocolOutcome::UnsupportedByStrategy,
            QqProtocolOutcome::ResponseShapeMismatch,
            QqProtocolOutcome::IncompleteData,
        ] {
            assert_eq!(outcome.decision(), QqStrategyDecision::TryNext);
        }
        assert_eq!(
            QqProtocolOutcome::TemporaryNetworkFailure.decision(),
            QqStrategyDecision::RetryBoundedly
        );
        for outcome in [QqProtocolOutcome::Success, QqProtocolOutcome::ValidEmpty] {
            assert_eq!(outcome.decision(), QqStrategyDecision::Return);
        }
    }

    #[test]
    fn authorization_content_and_risk_outcomes_stop() {
        for outcome in [
            QqProtocolOutcome::AuthenticationRequired,
            QqProtocolOutcome::RateLimited,
            QqProtocolOutcome::SecurityVerificationRequired,
            QqProtocolOutcome::CredentialRejected,
            QqProtocolOutcome::AccountRestricted,
            QqProtocolOutcome::DeviceRestricted,
            QqProtocolOutcome::VipRequired,
            QqProtocolOutcome::EntitlementDenied,
            QqProtocolOutcome::CopyrightRestricted,
            QqProtocolOutcome::RegionRestricted,
            QqProtocolOutcome::UpstreamUnknown,
        ] {
            assert_eq!(outcome.decision(), QqStrategyDecision::Stop);
        }
    }

    #[test]
    fn musicu_rate_limit_is_not_an_empty_or_fallback_safe_outcome() {
        assert_eq!(classify_musicu_codes(0, Some(0)), Ok(()));
        assert_eq!(classify_musicu_codes(0, None), Ok(()));
        assert_eq!(
            classify_musicu_codes(2001, Some(0)),
            Err(QqProtocolOutcome::RateLimited)
        );
        assert_eq!(
            classify_musicu_codes(0, Some(2001)),
            Err(QqProtocolOutcome::RateLimited)
        );
        assert_eq!(
            classify_musicu_codes(123, Some(0)),
            Err(QqProtocolOutcome::UpstreamUnknown)
        );
    }
}
