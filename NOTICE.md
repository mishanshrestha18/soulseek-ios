# Third-Party Notices

## SeeleseekCore

`Packages/SeeleseekCore/` is vendored from **seeleseek**, a native macOS
Soulseek client by Brett Henderson / COMPUTER DATA / The Virtuous Corporation.

- Upstream: https://github.com/bretth18/seeleseek
- License: MIT (see `LICENSE.seeleseek`)
- Vendored at commit: `e504f377e7be76c5f6bfcab41600f8dc706acfd9` (2026-09-19)

The Sources tree is vendored unmodified. The test target has been extended
with protocol tests lifted from the upstream app target (`seeleseekTests/`),
which are also MIT-licensed. See `UPSTREAM.md` for the sync procedure.

## GeoIP2-Country-Test.mmdb

`Packages/SeeleseekCore/Tests/SeeleseekCoreTests/Fixtures/GeoIP2-Country-Test.mmdb`
is MaxMind's public test fixture, Apache-2.0.
Source: https://github.com/maxmind/MaxMind-DB/tree/main/test-data
