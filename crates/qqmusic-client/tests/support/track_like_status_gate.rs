use std::collections::HashSet;

use qqmusic_client::{
    Credential, HttpTransport, QqMusicClient, QqMusicTrackLikeStatus, QqMusicTrackLikeStatusError,
};

const MAX_SNAPSHOT_PAGES: usize = 20;
const SNAPSHOT_PAGE_SIZE: u32 = 100;

#[derive(Clone, Copy)]
struct PublicSample {
    track_id: u64,
    song_type: u32,
    song_mid: &'static str,
}

struct ExistingLikedTarget {
    track_id: u64,
    song_type: u32,
    song_mid: String,
}

// Public catalog identities used only as opaque read targets. They come from
// public upstream fixtures, are never printed, and are not account-derived.
// The resolver comparison deliberately binds each MID to the exact numeric
// membership identity before comparing two operation-specific resolvers.
const PUBLIC_SAMPLES: [PublicSample; 2] = [
    PublicSample {
        track_id: 214_982_607,
        song_type: 0,
        song_mid: "0010JX7W3lWmvS",
    },
    PublicSample {
        track_id: 277_845_939,
        song_type: 0,
        song_mid: "002nuiuX04qN73",
    },
];

fn counts(statuses: &[QqMusicTrackLikeStatus]) -> (usize, usize, usize) {
    let liked = statuses
        .iter()
        .filter(|status| **status == QqMusicTrackLikeStatus::Liked)
        .count();
    let not_liked = statuses
        .iter()
        .filter(|status| **status == QqMusicTrackLikeStatus::NotLiked)
        .count();
    (liked, not_liked, statuses.len() - liked - not_liked)
}

fn report_error<E>(phase: &str, error: &QqMusicTrackLikeStatusError<E>) {
    match error {
        QqMusicTrackLikeStatusError::RateLimited => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=true http_status=429 global_code=none subrequest_code=none failure=rate_limited"
        ),
        QqMusicTrackLikeStatusError::HttpStatus(status) => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=true http_status={status} global_code=none subrequest_code=none failure=http_status"
        ),
        QqMusicTrackLikeStatusError::Rejected { code } => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=true http_status=2xx global_code=unknown subrequest_code=unknown rejection_code={code} failure=credential_rejected"
        ),
        QqMusicTrackLikeStatusError::Upstream {
            global_code,
            result_code,
        } => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=true http_status=2xx global_code={global_code} subrequest_code={} failure=upstream",
            result_code.map_or_else(|| "unknown".to_owned(), |code| code.to_string())
        ),
        QqMusicTrackLikeStatusError::Transport(_) => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=true http_status=unavailable global_code=none subrequest_code=none failure=transport"
        ),
        QqMusicTrackLikeStatusError::InvalidBatchSize { .. }
        | QqMusicTrackLikeStatusError::InvalidSongMid { .. }
        | QqMusicTrackLikeStatusError::DuplicateSongMid { .. } => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=false http_status=not_sent global_code=none subrequest_code=none failure=local_preflight"
        ),
        QqMusicTrackLikeStatusError::Serialize => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=false http_status=not_sent global_code=none subrequest_code=none failure=serialize"
        ),
        QqMusicTrackLikeStatusError::InvalidJson
        | QqMusicTrackLikeStatusError::MissingGlobalCode
        | QqMusicTrackLikeStatusError::MissingResult
        | QqMusicTrackLikeStatusError::MissingResultCode
        | QqMusicTrackLikeStatusError::MissingData
        | QqMusicTrackLikeStatusError::MissingStatusMap => eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase={phase} request_sent=true http_status=2xx global_code=unknown subrequest_code=unknown failure=invalid_response"
        ),
    }
}

pub async fn run_queries<T>(client: &QqMusicClient<T>, credential: &Credential) -> bool
where
    T: HttpTransport,
{
    let mids = PUBLIC_SAMPLES.map(|sample| sample.song_mid);
    eprintln!(
        "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=preflight login_type={} status_request_budget=2 snapshot_page_budget={MAX_SNAPSHOT_PAGES} production_enabled=false",
        credential.login_type().value()
    );

    let single = match client.track_like_statuses(credential, &mids[..1]).await {
        Ok(result) => result,
        Err(error) => {
            report_error("single", &error);
            return false;
        }
    };
    let (liked, not_liked, unknown) = counts(single.statuses());
    eprintln!(
        "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=single request_sent=true batch_size=1 http_status=2xx global_code=0 subrequest_code=0 response_key_count={} true_count={liked} false_count={not_liked} unknown_count={unknown} failure=none",
        single.response_key_count()
    );

    let batch = match client.track_like_statuses(credential, &mids).await {
        Ok(result) => result,
        Err(error) => {
            report_error("batch", &error);
            return false;
        }
    };
    let (liked, not_liked, unknown) = counts(batch.statuses());
    eprintln!(
        "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=batch request_sent=true batch_size=2 http_status=2xx global_code=0 subrequest_code=0 response_key_count={} true_count={liked} false_count={not_liked} unknown_count={unknown} failure=none",
        batch.response_key_count()
    );
    if single.statuses()[0] != batch.statuses()[0] {
        eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=direct_consistency result=BLOCKED failure=direct_status_changed_without_mutation"
        );
        return false;
    }
    compare_with_full_snapshot(
        client,
        credential,
        [batch.statuses()[0], batch.statuses()[1]],
    )
    .await
}

/// Closes only the positive boolean evidence gap. The target is selected from
/// the complete exact snapshot in memory, never supplied externally or logged.
pub async fn run_true_query<T>(client: &QqMusicClient<T>, credential: &Credential) -> bool
where
    T: HttpTransport,
{
    let mut membership = HashSet::new();
    let mut candidates = Vec::new();
    let mut exact = true;
    let mut offset = 0;
    let mut complete = false;
    let mut pages = 0;
    while pages < MAX_SNAPSHOT_PAGES {
        let Ok(page) = client
            .liked_songs_page(credential, offset, SNAPSHOT_PAGE_SIZE)
            .await
        else {
            eprintln!(
                "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=snapshot snapshot_complete=false membership_exact=false liked_target_available=false direct_true_test=NOT_RUN failure=snapshot_read_failed"
            );
            return false;
        };
        pages += 1;
        exact &= page.membership_is_exact();
        membership.extend(
            page.membership_identities()
                .iter()
                .map(|identity| (identity.track_id(), identity.song_type())),
        );
        candidates.extend(page.tracks().iter().map(|track| ExistingLikedTarget {
            track_id: track.track_id(),
            song_type: track.song_type(),
            song_mid: track.song_mid().to_owned(),
        }));
        if !page.has_more() {
            complete = true;
            break;
        }
        offset = page.next_offset();
    }

    eprintln!(
        "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=snapshot snapshot_complete={complete} membership_exact={exact} page_count={pages}"
    );
    if !complete || !exact {
        eprintln!(
            "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=target liked_target_available=false direct_true_test=NOT_RUN failure=snapshot_not_complete_exact"
        );
        return false;
    }

    let Some(target) = select_existing_liked_target(&membership, &candidates) else {
        eprintln!(
            "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=target liked_target_available=false direct_true_test=NOT_RUN"
        );
        return false;
    };
    eprintln!(
        "FURA_QQ_TRACK_LIKE_TRUE_GATE phase=target liked_target_available=true target_count=1 snapshot_state=liked"
    );

    let result = match client
        .track_like_statuses(credential, &[target.song_mid.as_str()])
        .await
    {
        Ok(result) => result,
        Err(error) => {
            report_error("true", &error);
            eprintln!(
                "FURA_QQ_TRACK_LIKE_TRUE_GATE login_type={} target_count=1 snapshot_state=liked request_sent=true http_status=unknown global_code=unknown subrequest_code=unknown direct_state=unknown agreement=false",
                credential.login_type().value()
            );
            return false;
        }
    };
    let direct = result.statuses()[0];
    let agreement = direct == QqMusicTrackLikeStatus::Liked;
    eprintln!(
        "FURA_QQ_TRACK_LIKE_TRUE_GATE login_type={} target_count=1 snapshot_state=liked request_sent=true http_status=2xx global_code=0 subrequest_code=0 direct_state={} agreement={agreement}",
        credential.login_type().value(),
        state_label(direct)
    );
    match direct {
        QqMusicTrackLikeStatus::Liked => {}
        QqMusicTrackLikeStatus::NotLiked => eprintln!(
            "FURA_QQ_TRACK_LIKE_TRUE_GATE result=AUTHORITATIVE_CONFLICT production_promotion=BLOCKED"
        ),
        QqMusicTrackLikeStatus::Unknown => {
            eprintln!("FURA_QQ_TRACK_LIKE_TRUE_GATE result=UNKNOWN production_promotion=BLOCKED");
        }
    }
    agreement
}

fn select_existing_liked_target<'a>(
    membership: &HashSet<(u64, u32)>,
    candidates: &'a [ExistingLikedTarget],
) -> Option<&'a ExistingLikedTarget> {
    candidates.iter().find(|candidate| {
        membership.contains(&(candidate.track_id, candidate.song_type))
            && is_valid_direct_mid(&candidate.song_mid)
    })
}

fn is_valid_direct_mid(song_mid: &str) -> bool {
    !song_mid.is_empty()
        && song_mid.len() <= 64
        && song_mid.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

async fn compare_with_full_snapshot<T>(
    client: &QqMusicClient<T>,
    credential: &Credential,
    direct: [QqMusicTrackLikeStatus; 2],
) -> bool
where
    T: HttpTransport,
{
    let mut membership = HashSet::new();
    let mut exact = true;
    let mut offset = 0;
    let mut complete = false;
    let mut pages = 0;
    while pages < MAX_SNAPSHOT_PAGES {
        let Ok(page) = client
            .liked_songs_page(credential, offset, SNAPSHOT_PAGE_SIZE)
            .await
        else {
            eprintln!(
                "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=resolver_disagreement result=BLOCKED failure=snapshot_read_failed"
            );
            return false;
        };
        pages += 1;
        exact &= page.membership_is_exact();
        membership.extend(
            page.membership_identities()
                .iter()
                .map(|identity| (identity.track_id(), identity.song_type())),
        );
        if !page.has_more() {
            complete = true;
            break;
        }
        offset = page.next_offset();
    }
    if !complete {
        eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=resolver_disagreement result=BLOCKED failure=snapshot_page_budget_exhausted"
        );
        return false;
    }

    let snapshot = PUBLIC_SAMPLES.map(|sample| snapshot_state(&membership, exact, sample));
    let mut accepted = true;
    for (snapshot_state, direct_state) in snapshot.into_iter().zip(direct) {
        let agreement = snapshot_state == direct_state;
        eprintln!(
            "agreement={agreement} snapshot_state={} direct_state={}",
            state_label(snapshot_state),
            state_label(direct_state)
        );
        if !agreement
            || snapshot_state == QqMusicTrackLikeStatus::Unknown
            || direct_state == QqMusicTrackLikeStatus::Unknown
        {
            accepted = false;
        }
    }
    if !accepted {
        eprintln!(
            "FURA_QQ_TRACK_LIKE_STATUS_GATE phase=resolver_disagreement result=BLOCKED failure=unexplained_resolver_disagreement_or_unknown"
        );
    }
    accepted
}

fn snapshot_state(
    membership: &HashSet<(u64, u32)>,
    exact: bool,
    sample: PublicSample,
) -> QqMusicTrackLikeStatus {
    if membership.contains(&(sample.track_id, sample.song_type)) {
        QqMusicTrackLikeStatus::Liked
    } else if exact {
        QqMusicTrackLikeStatus::NotLiked
    } else {
        QqMusicTrackLikeStatus::Unknown
    }
}

const fn state_label(status: QqMusicTrackLikeStatus) -> &'static str {
    match status {
        QqMusicTrackLikeStatus::Liked => "liked",
        QqMusicTrackLikeStatus::NotLiked => "notLiked",
        QqMusicTrackLikeStatus::Unknown => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use qqmusic_client::QqMusicTrackLikeStatus;

    use super::{
        ExistingLikedTarget, PUBLIC_SAMPLES, select_existing_liked_target, snapshot_state,
    };

    #[test]
    fn public_samples_are_bounded_and_not_diagnostics() {
        assert_eq!(PUBLIC_SAMPLES.len(), 2);
        for sample in PUBLIC_SAMPLES {
            assert_ne!(sample.track_id, 0);
            assert!(!sample.song_mid.is_empty());
            assert!(
                sample
                    .song_mid
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric())
            );
        }
    }

    #[test]
    fn snapshot_negative_requires_complete_exact_membership() {
        let sample = PUBLIC_SAMPLES[0];
        let empty = HashSet::new();
        assert_eq!(
            snapshot_state(&empty, false, sample),
            QqMusicTrackLikeStatus::Unknown
        );
        assert_eq!(
            snapshot_state(&empty, true, sample),
            QqMusicTrackLikeStatus::NotLiked
        );

        let membership = HashSet::from([(sample.track_id, sample.song_type)]);
        assert_eq!(
            snapshot_state(&membership, false, sample),
            QqMusicTrackLikeStatus::Liked
        );
    }

    #[test]
    fn true_target_requires_canonical_membership_and_valid_mid() {
        let candidates = [
            ExistingLikedTarget {
                track_id: 10,
                song_type: 0,
                song_mid: "invalid mid".to_owned(),
            },
            ExistingLikedTarget {
                track_id: 11,
                song_type: 1,
                song_mid: "ValidMid11".to_owned(),
            },
            ExistingLikedTarget {
                track_id: 12,
                song_type: 0,
                song_mid: "ValidMid12".to_owned(),
            },
        ];
        let membership = HashSet::from([(12, 0)]);
        let target = select_existing_liked_target(&membership, &candidates)
            .expect("one canonical liked target");
        assert_eq!(target.track_id, 12);

        assert!(select_existing_liked_target(&HashSet::new(), &candidates).is_none());
    }
}
