//! Disabled legacy manual-secret entry. The isolated CDP gate is a Rust caller
//! receiving an existing `TrackId`; this example never reads secrets or starts IO.
fn main() {
    println!(
        "KUGOU_GATE result=NOT_RUN reason=OFFICIAL_WEB_CDP_OWNER_REQUIRED production_enabled=false"
    );
}
