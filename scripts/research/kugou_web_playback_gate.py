#!/usr/bin/env python3
"""Retired CLI: only a Rust caller with the current Fura KuGou TrackId may run.

Arguments, stdin and environment are not read; no standalone target is available.
"""


def main() -> int:
    print("KUGOU_GATE result=NOT_RUN reason=RUST_CALLER_REQUIRED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
