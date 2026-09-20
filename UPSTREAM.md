# Syncing with upstream seeleseek

`Packages/SeeleseekCore/Sources/` is a verbatim vendor of upstream. Keep it
that way — every local change to that tree is a merge conflict you pay for on
every sync. Portability fixes belong upstream; send them there first.

## Pinned commit

    e504f377e7be76c5f6bfcab41600f8dc706acfd9   2026-09-19

Update this file *and* `NOTICE.md` whenever the pin moves.

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
