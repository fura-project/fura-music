# QQ Music lyric and QRC evidence

- **Status:** Anonymous/authenticated Client and Provider mapping implemented; live anonymous QRC path passed; line-timed compatibility and optional-track isolation fixture-verified
- **Last checked:** 2026-09-03
- **Scope:** One QQ Music track's synchronized original lyrics, optional translation/romanization, and basic word-level timing for M1.

This note records independently implemented behavior plus one bounded anonymous response-shape probe. It does not retain or reproduce lyric text, encrypted lyric bodies, account data, or reusable third-party source code.

## Sources inspected

1. [L-1124/QQMusicApi at `108617f`](https://github.com/L-1124/QQMusicApi/tree/108617ffe80abefec6358717b9f4d3677550db10), especially [`modules/lyric.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/modules/lyric.py), [`models/lyric.py`](https://github.com/L-1124/QQMusicApi/blob/108617ffe80abefec6358717b9f4d3677550db10/qqmusic_api/models/lyric.py), and its QRC decoder. This is the current musicu request/response reference.
2. [jixunmoe-go/qrc at `866e996`](https://github.com/jixunmoe-go/qrc/tree/866e996416b0cec7bef648400633f6483c4200d5), an independent MIT-licensed decoder. Its three QQ-compatible DES passes and zlib output corroborate the cloud decoder without depending on a general-purpose standard Triple-DES implementation.
3. [tomakino/qrckit at `b2a6ced`](https://github.com/tomakino/qrckit/tree/b2a6ced65d88b632edad2022d24898cf9480180a), especially its QRC parser and decryptor. The inspected source files carry Apache-2.0 headers and independently corroborate the encrypted fields, XML wrapper, timing grammar, and translation/romanization separation.
4. [chenmozhijin/LDDC at `84631e8`](https://github.com/chenmozhijin/LDDC/tree/84631e8cd011fcc3f71ca0ae017e2c9758958ffc), especially its QRC parser/decryptor. This GPL-3.0-only source is evidence only and must not be copied into the project. Its parser independently agrees on line and token timing semantics.
5. [yakult-green-tea/qq-music-api at `2c27d6b`](https://github.com/yakult-green-tea/qq-music-api/tree/2c27d6b90dd56bcf0796883e27216f69189d8f68) and [feeluown/feeluown-qqmusic at `241a967`](https://github.com/feeluown/feeluown-qqmusic/tree/241a9678bcd26e88d19e08e5da8048018f06e330) both still implement `fcg_query_lyric_new.fcg` plus Base64 LRC. They corroborate a line-level compatibility path only; they do not establish the M1 word-level path.

## Current musicu operation

The selected request is:

```text
POST https://u.y.qq.com/cgi-bin/musicu.fcg
module music.musichallSong.PlayLyricInfo
method GetPlayLyricInfo
```

The minimum evidenced parameter set is:

```text
songMid: QQ song MID
type: QQ song type
crypt: 1
qrc: 1
qrc_t: 0
lrc_t: 0
trans: 1
trans_t: 0
roma: 1
roma_t: 0
```

The pinned current client uses `songMid`; the 2026-08-26 probe used that exact spelling successfully. Other implementations use `songMID`, but this project must not rely on undocumented alias acceptance when it has a directly verified form. The opaque QQ track identity already preserves MID and song type inside `QQMusicProvider`; no QQ identity parsing belongs in Domain, Bridge, or Flutter.

The response is a normal musicu envelope with global and named-request codes. Its data includes:

```text
songID
songType
crypt
qrc
lyric
trans
roma
lrc_t
qrc_t
trans_t
roma_t
```

When QRC is requested, `lyric` carries the encrypted original lyric; there is not a separate string-valued `qrc` body in the observed response. `qrc` and `crypt` are representation flags. `trans` and `roma` are independent optional encrypted strings and may be empty on a successful response. Their absence is not a protocol failure. Current external implementations also decrypt those optional fields independently rather than making them prerequisites for a usable original track.

The `*_t` values are upstream revision/timestamp metadata, not playback positions. Their exact epoch/unit and cache semantics are not required for the first slice and must not be exposed as lyric timing.

## Cloud QRC decoding boundary

Three independent decoders agree on the cloud pipeline:

```text
hex string
↓
QQ-compatible DES decrypt/encrypt/decrypt block sequence
↓
zlib decompression
↓
UTF-8 text
```

The concatenated key is `!@#)(*$%123ZXC!@!@#)(NHL`; the independent Go implementation expresses the same operation as three eight-byte keys. This is QQ compatibility behavior, not ordinary standards-compliant Triple-DES: the current Python implementation explicitly preserves QQ's historical key-schedule/table behavior. A generic DES/3DES package must not be assumed compatible without a known-answer test.

The separate QMC-wrapped local `.qrc` format can carry an eleven-byte magic header and an additional local-file transform. The musicu cloud response is hex text and does not use that wrapper. Local QRC files are outside M1 and must not expand this task.

The first implementation should keep decryption inside `qqmusic-client`, bound input/output sizes, require even-length hexadecimal input and complete eight-byte cipher blocks, reject invalid zlib/UTF-8 output, and expose no plaintext or ciphertext in diagnostics. A synthetic known-answer vector may be derived from non-lyrical project-authored text. Do not commit captured commercial lyrics as fixtures.

## QRC text grammar and time semantics

The decoded cloud value is an XML document whose relevant payload is the `LyricContent` attribute of a `Lyric_1` element with lyric type `1`. XML entities must be decoded before parsing the embedded QRC text. A regular expression alone is not sufficient for attribute extraction because lyric text can contain escaped quotes, ampersands, and angle brackets.

The independently corroborated embedded grammar is:

```text
[metadata-key:metadata-value]
[line-start-ms,line-duration-ms]token(token-start-ms,token-duration-ms)...
```

Both line and token pairs are absolute start time plus duration in milliseconds. End time is checked addition of start and duration. Token text can be a character, punctuation, whitespace, or a multi-character chunk, so the provider-neutral model should call it a segment/token rather than claim linguistic word segmentation.

The parser should preserve source order and content, use checked unsigned millisecond arithmetic, and reject malformed required timing instead of silently coercing it to zero. Evidence does not justify rejecting overlapping lines, gaps, tokens that extend slightly outside their line, or empty timed lines; those may be real upstream data. Sorting, fuzzy alignment, and invented terminal durations are presentation/mapping policy and are not part of the raw QRC parser.

## Translation and romanization

The response returns translation and romanization as separate optional lyric documents. Current independent presentation code treats them as line-timed tracks and aligns them to original lines by timing, not by array position. The exact tolerance is implementation policy and has not been cross-validated.

For the first slice:

- parse original QRC into timed lines and timed segments;
- parse nonempty translation/romanization as independent timed line tracks;
- let the Provider perform only exact-start alignment initially;
- keep unmatched auxiliary lines absent rather than attaching text to the wrong original line;
- do not invent fuzzy matching until sanitized real evidence establishes a tolerance.

Translation and romanization do not require word-level segments for M1. Empty auxiliary fields remain a valid successful lyric result. A malformed nonempty optional track is now isolated: the valid original is returned, the unusable optional track is omitted, and an opt-in content-free diagnostic identifies only the optional track and failure field. The auxiliary decoder accepts both line-timed LRC and QRC-shaped documents but retains only line text/start time for Provider alignment.

The same `PlayLyricInfo` response can also truthfully represent an encrypted line-timed original when the response marks `qrc: 0`. Fura now maps that LRC into synchronized lines with zero source duration and no word segments. It does not synthesize word timing or a terminal duration; presentation keeps the latest started line selected until another line begins. This compatibility path is covered by a project-authored encrypted known-answer fixture but is not yet claimed as live catalog coverage.

QQ's decrypted cloud-QRC envelope is XML-shaped but its `LyricContent` value is not guaranteed to use strict XML entity escaping. A maintainer rerun of a public Track whose title contains an ampersand produced the content-free stage `original.invalid_xml`; that is consistent with an unescaped XML-reserved character inside this content attribute, and an active independent QRC parser likewise extracts that attribute without requiring its lyric text to be strict XML. Fura continues using the XML reader for element/attribute structure, but applies a bounded QQ-specific decoder to the raw `LyricContent` value: valid named/numeric entities are decoded, while unknown or literal ampersands remain lyric text. The existing two-megabyte decrypted-text limit still applies. Project-authored fixtures cover the ampersand and unknown-entity cases; the reported real Track still requires a maintainer rerun because no lyric body was captured.

## Controlled live probe

On 2026-08-26 an anonymous request for the public song MID already used by the repository's no-account media test returned HTTP JSON with global code `0`, named-request code `0`, `crypt: 1`, `qrc: 1`, and `songType: 0`. The `lyric` field was a nonempty even-length hexadecimal string; `trans` and `roma` existed but were empty for that sample. The data object also contained the documented revision fields and optional singing-annotation metadata.

The probe printed only codes, field names, types, lengths, flags, and nonempty booleans. It did not print or retain the encrypted body or decoded lyrics. This proves the anonymous request and response shape on that date. It does not prove authenticated behavior, lyric availability across the catalog, translation/romanization coverage, decryption correctness in this project, or exact timing behavior for a real track.

After implementation, the opt-in Rust `live_lyrics` test ran the same public MID through the actual bounded client request, QQ-compatible decryptor, XML reader, and QRC parser. It confirmed a nonempty original line set with at least one timed segment without printing or retaining ciphertext or lyric text. On 2026-09-01 the gate passed again with no Cookie and only zero/empty anonymous account fields; the Provider now uses this path while signed out instead of rejecting before transport. On 2026-09-03 the same one-request anonymous gate passed after the compatibility change. This proves the implemented anonymous request/decode/parse path for that public QRC sample; it still does not prove the line-timed branch, authenticated-only outcomes, or auxiliary-track coverage across the catalog.

For a maintainer-operated failing Track, setting `FURA_QQ_LYRIC_DEBUG=1` before launching the app prints only a stable failure stage or optional-track field plus line counts. It never prints the song MID, account data, Cookie, ciphertext, plaintext, media URL, or response body. This is a temporary evidence mechanism for distinguishing identity/representation/cipher/parser failures without collecting protected content.

## Selected first implementation slice

1. Add provider-neutral timed lyric lines/segments and optional aligned translation/romanization to `music-domain`, with constructor invariants and synthetic tests. **Completed.**
2. Add a narrow `LyricsProvider` contract keyed by opaque `TrackId`; do not expose encrypted fields, QQ revision metadata, or raw QRC.
3. Add one bounded `QQMusicClient::lyrics` musicu operation, QQ-compatible cloud decryption, XML/QRC parsing, and wholly synthetic non-lyrical fixtures. **Completed.**
4. Map exact-start auxiliary lines in `QQMusicProvider`, rechecking the exact credential after the await and clearing it only on explicit rejection.
5. Add a cancellable Bridge load handle, then compose loading and playback-position presentation in Flutter without moving protocol or parsing logic into Dart.

## Evidence still required

1. A sanitized real-account integration proving authenticated lyric outcomes; the anonymous implemented request/decrypt/parse path is now live-proven without retaining its body.
2. A non-copyrighted or privately inspected sample with nonempty translation and romanization to confirm their decoded document forms and timestamp alignment.
3. Sanitized malformed/empty/no-lyric and credential-rejection outcomes before assigning more specific product messages.
4. Real playback-position smoke proving active line/segment transitions and seek behavior; widget clocks alone will not establish plugin event correctness.
5. A maintainer rerun of the reported ampersand-title failure after the bounded pseudo-XML compatibility fix. If it remains unavailable, capture only the new `FURA_QQ_LYRIC_DEBUG=1` stage; a numeric-song-ID or alternate-endpoint route requires evidence that the remaining failure occurs outside local decoding.
6. Mobile runtime/build evidence before the M1 checkpoint.
