# Human Decisions

## HD-001 — Release identity and signing custody

**Status:** Pending

**Context:** M1 packaging has produced development Android and Linux artifacts, so TD-002's packaging trigger is satisfied. Android release builds still use development signing and the platform shells still use generated identity. No artifact has been authorized for external distribution.

**Decision needed:** The human maintainer defines the final product/display name, per-platform application identifiers, and the secret-safe ownership and custody workflow for release signing keys before external distribution.

**Options:**

1. Keep the current working product name and define final platform identifiers plus signing custody.
2. Choose a different final product name and corresponding platform identifiers plus signing custody before release setup.

**Blocked work:**

- Resolving TD-002.
- Production release identity and signing setup.
- Distribution of artifacts outside development.

**Not blocked:**

- The remaining M1 real-account playback, queue, and lyric acceptance observation.
- Independent M2 reliability, accessibility, and daily-use work.
- Development-signed local builds and tests.
- QQ Music Provider/Core work within the Roadmap.

**Current agent action:** Continue unrelated Roadmap work and keep generated or development-signed artifacts development-only.

## HD-002 — Default Material baseline before theme personas

**Status:** Accepted on 2026-08-27

**Decision:** M4 first establishes a coherent official-Flutter Material 3 product baseline across desktop and compact/mobile. Quiet, Calm, Luminous, Temporal, artwork-derived global color, signature music motion, and other theme personas remain deferred until that baseline is stable. M4 does not introduce a third-party Material 3 Expressive library or a project-owned full M3 Expressive clone.

**Consequences:** Theme, adaptive shell, page hierarchy, component consistency, interaction states, accessibility, and daily-use product cohesion are authorized M4 work. Theme-plugin infrastructure, speculative design-system frameworks, navigation/state-management replacement, and experimental identity effects are not authorized by this decision.

When a decision is needed, record its context, options, blocked and unblocked work, and the current autonomous action. A pending decision blocks only its affected scope unless every legitimate task depends on it.
