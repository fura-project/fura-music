//! Research-only: one existing public Search -> Human ordinal -> existing CDP gate.
//! No protocol/identity construction, secret input, persistence or production caller.

use super::kugou;
use kugou_client::{Error, HttpsTransport, KuGouClient, Request, Response, Transport};
use music_domain::{TrackId, TrackSearchItem};
use nix::poll::{PollFd, PollFlags, poll};
use provider_api::{SearchError, TrackSearchProvider};
use provider_kugou::{KuGouProvider, web_playback_candidate::AuthenticatedStandardCandidate};
use std::fs::{File, OpenOptions};
use std::io::{self, IsTerminal, Read, Write};
use std::os::fd::AsFd;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

const MAX_PUBLIC_SEARCH_REQUESTS: u8 = 1;
const SEARCH_PAGE_SIZE: u32 = 10;
const AUTHORIZE_SEARCH: &str = "AUTHORIZE ONE PUBLIC SEARCH";
const AUTHORIZE_PLAYBACK: &str = "AUTHORIZE ONE AUTHENTICATED GATE";
const AUTHORIZE_RANGE: &str = "AUTHORIZE ONE RANGE";

/// Shared by every send on this instance, including a second workflow invocation
/// or concurrent calls. The budget is spent before any network await, never reset.
struct OneSearch<T> {
    transport: T,
    spent: AtomicBool,
}

impl<T> OneSearch<T> {
    fn new(transport: T) -> Self {
        Self {
            transport,
            spent: AtomicBool::new(false),
        }
    }
}

impl<T: Transport> Transport for OneSearch<T> {
    async fn send(&self, request: Request) -> Result<Response, Error> {
        if self.spent.swap(true, Ordering::SeqCst) {
            return Err(Error::InputBound);
        }
        self.transport.send(request).await
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Stop {
    SearchNotAuthorized,
    Cancelled,
    SearchFailed,
    EmptySearch,
    InvalidSelection,
    TrackContextUnavailable,
    PlaybackNotAuthorized,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Diagnostic {
    SearchBudget,
    ResultCount(u32),
    HumanSelection,
    PlaybackAuthority,
    Stopped(Stop),
}

impl std::fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::SearchBudget => write!(
                f,
                "KUGOU_HARNESS search_budget={MAX_PUBLIC_SEARCH_REQUESTS}"
            ),
            Self::ResultCount(count) => write!(f, "KUGOU_HARNESS search_result_count={count}"),
            Self::HumanSelection => f.write_str("KUGOU_HARNESS human_selection=CONFIRMED"),
            Self::PlaybackAuthority => f.write_str("KUGOU_HARNESS playback_authority=CONFIRMED"),
            Self::Stopped(stop) => {
                let reason = match stop {
                    Stop::SearchNotAuthorized => "SEARCH_NOT_AUTHORIZED",
                    Stop::Cancelled => "CANCELLED",
                    Stop::SearchFailed => "SEARCH_FAILED",
                    Stop::EmptySearch => "EMPTY_SEARCH",
                    Stop::InvalidSelection => "INVALID_SELECTION",
                    Stop::TrackContextUnavailable => "TRACK_CONTEXT_UNAVAILABLE",
                    Stop::PlaybackNotAuthorized => "PLAYBACK_NOT_AUTHORIZED",
                };
                write!(f, "KUGOU_HARNESS stop={reason}")
            }
        }
    }
}

// Presentation is a separate terminal-only channel, never a Diagnostic payload.
trait Interaction {
    fn approve_search(&mut self) -> bool;
    fn query(&mut self) -> Option<String>;
    fn selection(&mut self, items: &[TrackSearchItem]) -> Option<String>;
    fn approve_playback(&mut self) -> bool;
    fn approve_range(&mut self, hostname: &str, is_current: &impl Fn() -> bool) -> bool;
    fn diagnostic(&mut self, diagnostic: Diagnostic);
}

trait PlaybackGate {
    async fn enter(&self, id: &TrackId, interaction: &mut impl Interaction);
}

/// No preflight parser or duplicate TrackId codec: reuse existing Provider
/// admission on a validation-only owner with *no transport*. It is dropped here;
/// the actual one-shot CDP/replay owner is created only after Phase B approval.
fn eligible(id: &TrackId) -> bool {
    AuthenticatedStandardCandidate::new(())
        .begin_capture(id)
        .is_ok()
}

async fn workflow(
    provider: &impl TrackSearchProvider<Error = SearchError>,
    interaction: &mut impl Interaction,
    gate: &impl PlaybackGate,
) -> Result<(), Stop> {
    interaction.diagnostic(Diagnostic::SearchBudget);
    if !interaction.approve_search() {
        return Err(Stop::SearchNotAuthorized);
    }
    let query = interaction.query().ok_or(Stop::Cancelled)?;
    // Exactly one existing Provider search, always the first bounded page. No
    // pagination, retry, details, fallback or subsequent query exists here.
    let page = provider
        .search_tracks(query, 1, SEARCH_PAGE_SIZE)
        .await
        .map_err(|_| Stop::SearchFailed)?;
    let items = page.items();
    let count = u32::try_from(items.len())
        .ok()
        .filter(|count| *count <= SEARCH_PAGE_SIZE)
        .ok_or(Stop::SearchFailed)?;
    interaction.diagnostic(Diagnostic::ResultCount(count));
    if items.is_empty() {
        return Err(Stop::EmptySearch);
    }
    let input = interaction.selection(items).ok_or(Stop::Cancelled)?;
    let selected = selection_index(&input, items.len()).ok_or(Stop::InvalidSelection)?;
    // Keep the actual mapped TrackId, never rebuild it from presentation fields.
    let id = items[selected].track().id();
    if !eligible(id) {
        return Err(Stop::TrackContextUnavailable);
    }
    interaction.diagnostic(Diagnostic::HumanSelection);
    if !interaction.approve_playback() {
        return Err(Stop::PlaybackNotAuthorized);
    }
    interaction.diagnostic(Diagnostic::PlaybackAuthority);
    gate.enter(id, interaction).await;
    Ok(())
}

fn selection_index(input: &str, count: usize) -> Option<usize> {
    let input = input.trim();
    if input.is_empty() || !input.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    input
        .parse::<usize>()
        .ok()?
        .checked_sub(1)
        .filter(|i| *i < count)
}

struct ExistingGate;

impl PlaybackGate for ExistingGate {
    async fn enter(&self, id: &TrackId, interaction: &mut impl Interaction) {
        let Ok(transport) = kugou_client::web_playback_candidate::WebPlaybackHttpsTransport::new()
        else {
            println!("KUGOU_GATE result=BLOCKED reason=TRANSPORT_UNAVAILABLE");
            return;
        };
        let owner = Arc::new(AuthenticatedStandardCandidate::new(transport));
        let current = Arc::new(AtomicBool::new(true));
        // Install the cancellation signal before polling the browser future. Do
        // not abort/drop run_gate: it must finish its existing cleanup path.
        let Ok(mut interrupt) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())
        else {
            println!("KUGOU_GATE result=NOT_RUN");
            return;
        };
        let Ok(mut terminate) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        else {
            println!("KUGOU_GATE result=NOT_RUN");
            return;
        };
        let signal_owner = Arc::clone(&owner);
        let signal_current = Arc::clone(&current);
        // A separate runtime worker must be able to retire authority even while
        // the synchronous run_gate Range callback waits for terminal input.
        let cancellation = tokio::spawn(async move {
            tokio::select! {
                _ = interrupt.recv() => {},
                _ = terminate.recv() => {},
            }
            signal_current.store(false, Ordering::SeqCst);
            signal_owner.clear();
        });
        let is_current = || current.load(Ordering::SeqCst);
        let attempt = kugou::run_gate(
            &owner,
            id,
            true, // Reached only after the separate Phase B confirmation.
            is_current,
            |host| interaction.approve_range(host, &is_current),
        );
        await_gate_cleanup(attempt, cancellation).await;
        owner.clear();
    }
}

async fn await_gate_cleanup(
    attempt: impl std::future::Future,
    mut cancellation: tokio::task::JoinHandle<()>,
) {
    tokio::pin!(attempt);
    tokio::select! {
        _ = &mut attempt => {
            cancellation.abort();
            let _ = cancellation.await;
        },
        _ = &mut cancellation => {
            // Await existing cooperative browser cleanup, never abort/drop it.
            let _ = attempt.await;
        },
    }
}

struct Terminal {
    reader: File,
    display: File,
}

impl Terminal {
    fn open() -> io::Result<Self> {
        if !io::stdin().is_terminal() || !io::stdout().is_terminal() || !io::stderr().is_terminal()
        {
            return Err(io::ErrorKind::NotConnected.into());
        }
        // Presentation never goes through redirected stdout, a logger or a file.
        let tty = OpenOptions::new().read(true).write(true).open("/dev/tty")?;
        Ok(Self {
            reader: tty.try_clone()?,
            display: tty,
        })
    }

    fn line(&mut self, prompt: &str) -> Option<String> {
        self.line_while_current(prompt, &|| true)
    }

    fn line_while_current(
        &mut self,
        prompt: &str,
        is_current: &impl Fn() -> bool,
    ) -> Option<String> {
        write!(self.display, "{prompt}").ok()?;
        self.display.flush().ok()?;
        terminal_line(&mut self.reader, is_current)
    }

    fn confirm(&mut self, prompt: &str, phrase: &str) -> bool {
        self.line(&format!(
            "{prompt}\nType {phrase} to approve; anything else ends this phase: "
        ))
        .is_some_and(|line| line == phrase)
    }
}

fn terminal_line(
    reader: &mut (impl Read + AsFd),
    is_current: &impl Fn() -> bool,
) -> Option<String> {
    let mut line = Vec::new();
    while is_current() {
        let mut descriptors = [PollFd::new(reader.as_fd(), PollFlags::POLLIN)];
        match poll(&mut descriptors, 100u16) {
            Ok(0) | Err(nix::errno::Errno::EINTR) => continue,
            Ok(_) => {}
            Err(_) => return None,
        }
        if !is_current() {
            return None;
        }
        let mut byte = [0];
        if reader.read(&mut byte).ok()? != 1 {
            return None;
        }
        line.push(byte[0]);
        if byte[0] == b'\n' {
            return completed_line(&line);
        }
        if line.len() >= 258 {
            return None;
        }
    }
    None
}

fn completed_line(bytes: &[u8]) -> Option<String> {
    let line = std::str::from_utf8(bytes).ok()?;
    if line.len() > 258 || !line.ends_with('\n') {
        return None;
    }
    Some(line.trim_end_matches(['\r', '\n']).to_owned())
}

impl Interaction for Terminal {
    fn approve_search(&mut self) -> bool {
        self.confirm(
            "Phase A — Budget: 1 anonymous KuGou public Search request\nNo retry, second page, detail or fallback. Cancellation ends this run.",
            AUTHORIZE_SEARCH,
        )
    }

    fn query(&mut self) -> Option<String> {
        self.line("Search query (one attempt, empty/EOF cancels): ")
            .filter(|query| !query.trim().is_empty())
    }

    fn selection(&mut self, items: &[TrackSearchItem]) -> Option<String> {
        present_results(&mut self.display, items).ok()?;
        self.line("Select one result number (empty/EOF cancels; invalid input ends the run): ")
            .filter(|value| !value.trim().is_empty())
    }

    fn approve_playback(&mut self) -> bool {
        self.confirm(
            "Phase B — Authenticated playback gate\nA fresh isolated official KuGou Chromium browser will open. Human performs login, account/entitlement confirmation and selects this exact track on the website. Do not enter credentials here.\nThe browser-generated songinfo will be intercepted and aborted before network. After browser cleanup, Rust will send at most one real songinfo request. No retry/fallback.\nOptional one 4096-byte Range remains separately approved for the returned hostname. CAPTCHA/SSA, secondary verification, 429 or access denial stops the gate. Close the isolated browser to cancel.",
            AUTHORIZE_PLAYBACK,
        )
    }

    fn approve_range(&mut self, hostname: &str, is_current: &impl Fn() -> bool) -> bool {
        self.line_while_current(
            &format!("Optional Range — exactly one bytes=0-4095 request to {hostname}. No Cookie, retry or redirect. Decline to finish without a media request.\nType {AUTHORIZE_RANGE} to approve: "),
            is_current,
        ).is_some_and(|line| line == AUTHORIZE_RANGE && is_current())
    }

    fn diagnostic(&mut self, diagnostic: Diagnostic) {
        println!("{diagnostic}");
    }
}

fn present_results(display: &mut impl Write, items: &[TrackSearchItem]) -> io::Result<()> {
    for (index, item) in items.iter().enumerate() {
        let track = item.track();
        let duration = track.duration_seconds().unwrap_or_default();
        writeln!(
            display,
            "{}. {} | {} | {} | {}:{:02}",
            index + 1,
            track.title(),
            track.artist_names().join(" / "),
            track.album_title().unwrap_or("—"),
            duration / 60,
            duration % 60,
        )?;
    }
    Ok(())
}

pub(crate) fn main() {
    // No query, identity, file, browser profile or authority is accepted as an
    // argument/environment value. Even --interactive only opens the first prompt.
    if std::env::args_os().skip(1).collect::<Vec<_>>() != ["--interactive"] {
        println!("KUGOU_GATE result=NOT_RUN");
        return;
    }
    let Ok(mut terminal) = Terminal::open() else {
        println!("KUGOU_GATE result=NOT_RUN");
        return;
    };
    let Ok(transport) = HttpsTransport::new() else {
        println!("KUGOU_GATE result=NOT_RUN");
        return;
    };
    let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
    else {
        println!("KUGOU_GATE result=NOT_RUN");
        return;
    };
    let provider = KuGouProvider::new(KuGouClient::new(OneSearch::new(transport)));
    if let Err(stop) = runtime.block_on(workflow(&provider, &mut terminal, &ExistingGate)) {
        terminal.diagnostic(Diagnostic::Stopped(stop));
        println!("KUGOU_GATE result=NOT_RUN");
    }
}

#[cfg(test)]
mod tests;
