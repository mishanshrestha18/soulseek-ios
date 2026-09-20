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

### `0001-ios-default-gateway.patch`

`NATService.getDefaultGateway()` used `SCDynamicStoreCreate` /
`SCDynamicStoreCopyValue`, which are macOS-only — the two symbols were the
*only* thing preventing `SeeleseekCore` from compiling for iOS, despite the
package already declaring `.iOS(.v18)`.

The macOS path is unchanged, behind `#if os(macOS)`. Other platforms read the
default route's gateway out of the kernel routing table via
`sysctl(NET_RT_FLAGS)`. Both still fall back to the pre-existing `.1` on /24
heuristic.

Worth sending upstream: the package claims iOS support it does not have.

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
