# IPTV Integration Domain

This context defines the user-managed IPTV playlist subsystem integrated into GoPlay, enabling users to import, manage, and play external IPTV playlists, streams, and portals alongside curated events.

## Language

**IPTV Playlist**:
A user-imported structured collection of streaming channels, live broadcasts, or video-on-demand items.
_Avoid_: Channel list, subscription, cable feed.

**Playlist Source**:
The origin and ingestion protocol used to load an IPTV Playlist (M3U Remote URL, Local M3U File, Xtream Codes, Stalker/MAC Portal, or Direct Stream).
_Avoid_: Provider, link, host.

**Xtream Codes**:
An IPTV API standard authenticating via host URL, username, and password to retrieve live streams, VOD, series, and EPG categories.
_Avoid_: XC, Xtream server.

**Stalker Portal**:
An IPTV middleware architecture that authenticates client playback using a device MAC address and portal URL.
_Avoid_: MAG portal, STB server.

**Direct Network Stream**:
A standalone media streaming URL (HLS, DASH, MP4, TS) paired with optional ClearKey or Widevine DRM license configurations.
_Avoid_: Single link, video URL.

**EPG (Electronic Program Guide)**:
Standardized XMLTV metadata providing broadcast schedules and program details mapped to channel identifiers.
_Avoid_: Teleguide, TV schedule.
