---
name: allsvgicons
description: Find and insert real SVG icons and brand logos (Lucide, Material Design, Tabler, Heroicons, Phosphor, Font Awesome, flags, emoji and 230+ more open-source sets) through the allsvgicons MCP tools. Use when building or editing UI that needs an icon, a company logo, or a consistent icon set, instead of drawing SVG paths by hand.
---

# All SVG Icons

Use the allsvgicons MCP tools to put real, open-source SVG icons into code. Never draw icon paths by hand and never invent an icon name.

## Flow

1. `search_icons(query, prefix?, limit?, picker?)`: describe the icon by intent ("shopping cart outline", "settings gear"). Pass `prefix` to stay inside one set, for example `lucide` or `tabler`. `limit` is 1 to 20. Pass `picker: false` for searches the user does not need to see as an icon grid.
2. `get_icon(name)`: fetch the SVG for one `prefix:name` from the search results. Paste that markup as is. Icons over 32 KB (some emoji and flags) come back as a size and a URL instead of markup: download the file from that URL.
3. `find_brand_logo(brand)`: for company or product logos. Returns every version (color, mono, wordmark) and the brand's official hex color.
4. `list_collections()`: list every set, grouped by category, with prefix, name and icon count, when the user asks what is available or wants to pick a set. Call it once per conversation and reuse the result.

## Rules

- One project, one icon set. Check which set the codebase already uses (imports such as `lucide-react`, existing `prefix:name` strings, SVG class names) and pass that `prefix` to `search_icons`.
- Use only names that a tool returned. If `get_icon` reports a missing icon, search again. Do not guess a name or fabricate markup.
- Keep `currentColor` in the SVG so the icon follows the text color, unless the user asks for a fixed color. For brand logos, use the hex color from `find_brand_logo`.
- Add an accessible name where the icon carries meaning (`aria-label` or a visible label), and `aria-hidden="true"` where it is decoration.
- Fetch only the icons you will use. The free plan allows 20 calls a day (`list_collections` does not count); Pro lifts the cap. To save many icons as files, download `https://i.allsvgicons.com/<prefix>/<name>.svg` directly instead of calling `get_icon` for each.

## When the tools are missing

If no allsvgicons tools are available, the MCP server is not connected yet. Read https://allsvgicons.com/mcp.md and follow its setup steps, or tell the user to run `/mcp` in Claude Code and sign in to `allsvgicons`.
