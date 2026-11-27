# GoPlay Domain Glossary

Domain vocabulary for GoPlay live TV, sports events, IPTV playlists, playback, and monitoring.

## Catalog & Media

**Channel**:
A playable live stream entry identified by a deterministic ID, carrying a display name, category, optional stream servers, and optional DRM settings.
_Avoid_: Station, feed item

**Stream Server**:
One selectable backup source attached to a Channel so viewers or failover recovery can switch endpoints without leaving the channel.
_Avoid_: Link, mirror, source slot

**Live Event**:
A scheduled or ongoing sports match linking teams, league metadata, start window, and temporary encrypted or channel-mapped broadcast streams.
_Avoid_: Match card, game item

**Category Playlist**:
A live TV category backed by a remote M3U playlist synced directly by client devices without storing per-channel rows in Supabase.
_Avoid_: Direct category, remote group

**IPTV Playlist**:
A user-imported M3U, Xtream Codes, Stalker portal, or direct network stream playlist stored locally on the device.
_Avoid_: Local list, user source

**Catalog**:
The synchronized application snapshot combining database Channels, Category Playlists, Live Events, Announcements, hero banners, and remote UI configuration—persisted separately from local user preferences (favorites, tab layout).
_Avoid_: Sync cache, mixed app cache

## Playback & Navigation

**Playback Session**:
A resolved viewing context containing the target channel or Live Event, its expanded Stream Servers, its adjacent channel scope, and any active loading or failure state.
_Avoid_: Player launch map, playback context

**Nav Destination**:
A top-level shell destination that maps both a route branch and any coupled filter state (such as selecting the Favorites category on Channels).
_Avoid_: Tab target, menu route
