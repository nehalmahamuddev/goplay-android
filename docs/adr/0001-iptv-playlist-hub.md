# 1. Local IPTV Playlist Hub (`/iptv`)

GoPlay is designed as an event-first, operator-curated streaming app serving static metadata from Cloudflare R2 with zero video hosting cost. To satisfy user demand for custom IPTV playback without compromising the core product principles, we decided to introduce a self-contained, user-managed IPTV Hub under the `/iptv` route.

## Context and Decision

Users require playback of arbitrary M3U playlists, Xtream Codes accounts, Stalker/MAC portals, and direct DRM-protected streams. We considered merging external channels directly into the curated home catalog, but rejected this because it would pollute curated event-first schedules and violate GoPlay's verified metadata guarantees.

Instead, the `/iptv` screen operates as an isolated on-device client:
- Playlists and accounts are stored locally in dedicated Hive storage (`iptv_playlists`).
- The user catalog does not touch or alter the Cloudflare R2 / Supabase sync pipeline.
- Playback routes directly into GoPlay's high-performance `PlayerScreen` and `ChannelVideoPlayer`, reusing the existing playback state machine, ClearKey DRM engine, gestures, and PiP capabilities.
