# Soulseek for iOS

An iOS client for the [Soulseek](https://www.slsknet.org/) peer-to-peer
network. There is an Android client ([Seeker](https://github.com/jackBonadies/SeekerAndroid))
and a macOS one ([seeleseek](https://github.com/bretth18/seeleseek)); there is
no iOS one. This is that.

> **Working title.** Pick a real name before shipping — "Soulseek" is Nir
> Arbel's trademark and the app is unofficial.

## Status

Phase 1: proving the vendored protocol engine compiles and passes its test
suite on iOS. No UI yet.

## How Soulseek works

A central server for discovery, direct peer-to-peer TCP for everything that
carries bytes. All integers little-endian, all messages length-prefixed.

| Family        | Framing                 | Transport                    |
|---------------|-------------------------|------------------------------|
| Server        | `u32 len, u32 code`     | TCP → `server.slsknet.org:2242` |
| Peer init     | `u32 len, u8 code`      | first bytes on any peer socket |
| Peer (`P`)    | `u32 len, u32 code`     | peer ↔ peer                  |
| Distributed (`D`) | `u32 len, u8 code`  | search flood tree            |
| File (`F`)    | raw bytes, no codes     | bulk transfer                |

Strings are `u32` length + UTF-8 bytes.

**Login** (server code 1) sends username, password, a major version
identifying the client, `md5hex(username + password)`, and a minor version.
Major versions are a registry — `157` SoulseekQt, `160` Nicotine+, `169`
seeleseek, `170` Soulseek.NET, `177` experimental. Do not impersonate another
client's number.

**Search**: send `FileSearch` (26) with a self-generated token. The server
floods it across the distributed network. Peers holding matches connect *to
you* and send a zlib-compressed `FileSearchResponse` (peer code 9) carrying
filename, `u64` size, bitrate/duration attributes, free-slot flag, average
speed and queue length.

**Download**: `QueueUpload` (43) → peer answers `TransferRequest` (40) when
a slot frees → you answer `TransferResponse` (41) → peer opens an `F`
connection → you send a `u64` byte offset → raw file bytes stream until the
expected size is reached. The *downloader* closes the socket; the uploader
must not.

**Connecting to a peer** is the part that shapes the mobile design:

1. Send `ConnectToPeer` (18) to the server with a token and their username.
2. Send `GetPeerAddress` (3); server replies with their IP.
3. Dial them directly and send `PeerInit` (1).
4. Meanwhile the server relays your `ConnectToPeer` to them. If your direct
   dial failed, *they* dial *you* and send `PierceFireWall` (0) with the token.
5. Both directions fail → `CantConnectToPeer` (1001).

One side behind NAT is fine. Both behind NAT is a dead connection — there is
no relay and no hole-punching in the protocol.

Full reference: [SLSKPROTOCOL.md](https://github.com/nicotine-plus/nicotine-plus/blob/master/doc/SLSKPROTOCOL.md).

## Why this matters on iOS

- **Cellular is CGNAT.** Inbound connections never arrive, so every peer
  connection is indirect. Works fine unless the remote peer is also
  firewalled, in which case that peer is simply unreachable.
- **Backgrounding kills sockets.** `NWConnection` does not survive app
  suspension. Transfers are foreground-first; the protocol's `u64` file offset
  makes resume-on-relaunch cheap, and that is the plan rather than fighting
  iOS for background execution.
- **Distribution.** A P2P file-sharing client is an unlikely App Store
  approval. Realistic targets are a personal development certificate,
  AltStore/SideStore, or TestFlight.

## Architecture

    Packages/SeeleseekCore/   vendored protocol engine (MIT, upstream seeleseek)
      Sources/                  near-verbatim — see UPSTREAM.md before editing
      Tests/…/Protocol/         protocol tests lifted from upstream's app target
    App/
      project.yml               XcodeGen spec — the .xcodeproj is NOT committed
      Sources/                  iOS SwiftUI app
    Patches/                  every divergence from upstream, one file each
    .github/workflows/ci.yml  macOS runners: host tests, iOS build/test, app build

`SeeleseekCore` is 21k lines of Swift 6 with **zero external dependencies**,
built on `Network.framework` (`NWConnection`/`NWListener`), `Synchronization`,
`CryptoKit` and `Compression`. It imports no AppKit and already declares
`.iOS(.v18)`. It covers protocol codec, peer connection pooling, the
distributed search network, UPnP/NAT-PMP mapping, and download/upload
management.

The macOS app layer on top of it is not reused — that is 34k lines of
desktop SwiftUI, and the iOS UI is a fresh build.

## Building

Requires macOS with Xcode 16+ (Swift 6). There is no Swift toolchain on
Windows that provides `Network.framework`, so CI on `macos-26` runners is the
build environment.

    swift build --package-path Packages/SeeleseekCore
    swift test  --package-path Packages/SeeleseekCore

iOS compile check:

    cd Packages/SeeleseekCore
    xcodebuild build -scheme SeeleseekCore -destination 'generic/platform=iOS Simulator'

The app's `.xcodeproj` is generated rather than committed, because it can be
neither opened nor regenerated on Windows. `App/project.yml` is the source of
truth:

    brew install xcodegen
    cd App && xcodegen generate && open Soulseek.xcodeproj

## Roadmap

- [x] **Phase 1** — core builds for iOS device + simulator
- [ ] **Phase 1b** — ported protocol tests green on host and simulator
- [x] **Phase 2** — app shell: login, Keychain credentials, connection state
- [ ] **Phase 3** — Search: live result streaming done; filter/sort/grouping to do
- [ ] **Phase 4** — Download: queue, transfer UI, resume, file storage + Files.app export
- [ ] Later — uploads/sharing, audio player, chat and user browse

## Licensing

This project is MIT. `Packages/SeeleseekCore/` is vendored from seeleseek,
also MIT — see `NOTICE.md` and `LICENSE.seeleseek`.

Unofficial client. Not affiliated with Soulseek. Respect the
[server rules](https://www.slsknet.org/news/node/681): no automated scripting,
no randomly generated usernames.
