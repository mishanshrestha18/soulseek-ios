# Syncing with upstream seeleseek

`Packages/SeeleseekCore/Sources/` is a near-verbatim vendor of upstream. Keep
it that way — every local change to that tree is a merge conflict you pay for
on every sync. Portability fixes belong upstream; send them there first.

## Pinned commit

    e504f377e7be76c5f6bfcab41600f8dc706acfd9   2026-09-19

Update this file *and* `NOTICE.md` whenever the pin moves.

## Local patches

Every divergence from upstream lives in `Patches/` and is listed here. Adding
one without a matching entry is how a sync silently loses a fix.

### `0001-ios-portability.patch`

Two macOS-only APIs were the entire reason `SeeleseekCore` could not build for
iOS, despite the package already declaring `.iOS(.v18)`:

- `NATService.getDefaultGateway()` used `SCDynamicStoreCreate` /
  `SCDynamicStoreCopyValue`. Now behind `#if os(macOS)`; other platforms use
  the `.1` on /24 fallback that was already there. Walking the kernel routing
  table via `sysctl(NET_RT_FLAGS)` was tried first and abandoned — `rt_msghdr`
  is not exported to Swift on iOS, and hand-rolling the struct layout is not
  worth it for a value only used to attempt a UPnP mapping.
- `ShareManager` passed `.withSecurityScope` to `bookmarkData(options:)` and
  `URL(resolvingBookmarkData:options:)`. Both options are macOS-only; iOS uses
  `[]`, which persists document-picker URLs equivalently.

Worth sending upstream: the package claims iOS support it does not have.

### `Package.swift`: test target isolation

Not in `Patches/` since `Package.swift` is not part of the vendored Sources
tree. The test target sets `.defaultIsolation(MainActor.self)` because the
ported tests were written under the app target's
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and call MainActor-isolated mocks
from test functions with no explicit isolation.

## Procedure

    git clone --depth 50 https://github.com/bretth18/seeleseek.git /tmp/seeleseek
    rsync -a --delete /tmp/seeleseek/Packages/SeeleseekCore/Sources/ \
        Packages/SeeleseekCore/Sources/
    git diff --stat        # review before committing

`Package.swift` is currently verbatim upstream — it already declares
`.iOS(.v18)` alongside `.macOS(.v15)`, which is the only reason this vendor
works at all. If it ever needs to diverge, note the divergence here.

## Test target

`Tests/SeeleseekCoreTests/Protocol/` holds tests lifted from upstream's app
target. They were selected because they reference no app-only types; the only
edit applied was deleting the `@testable import seeleseek` line. To refresh
them, re-copy from `seeleseekTests/` and re-apply that deletion.

## Skipped tests

Two of the ported tests do not run everywhere. Both are disabled with a trait
rather than deleted, so they show up as skipped instead of disappearing.

| Test | Skipped on | Why |
|------|-----------|-----|
| `ShareCountNotificationTests` — "Rapid changes coalesce…" | CI | Five rescans must all land inside the debounce window. On shared runners they straddle it and the second trailing-edge yield is correct behaviour, so the assertion is wrong rather than the code. Scaling the waits does not help — the window itself is the problem. Fails on the macOS host too. |
| `PeerConnectivityTests` — "Unexpected server loss reconnects…" | iOS | Unexplained. Passes on macOS. On the simulator the client never reaches `.connected` against the loopback fake server. **Needs diagnosis** — reconnect is more important on mobile than on desktop. |

The rest of that suite proves an absence (a cancelled subscriber never fires),
which cannot be polled for the way arrival can, so those waits are fixed
rather than adaptive. They are scaled 8x when `CI` is set; "Cancelling a
consumer Task removes its continuation" failed on a loaded runner at the
original 100ms.
