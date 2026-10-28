# CLAUDE.md

Collection of proof-of-concept roguelike games, each published as a Claude Artifact by default. See `README.md` for layout and the game index.

## Conventions

- One game per `games/<slug>/`, entry point `index.html`, single file by default (inline CSS + JS).
- No build tooling, no package manager, no backend. Open the file in a browser to run it.
- Update the games table in `README.md` whenever a game is added or its status changes. Update docs in place; do not create new markdown files per task.
- Keep comments minimal: only for non-obvious logic.

## Artifact constraints

Load the `artifact-design` skill before writing or republishing a game; it is authoritative. Key points:

- `<title>` is a 2-4 word name, not "Name: explainer". Put the pitch in the publish `description`.
- External scripts only from cdnjs.cloudflare.com (preferred), cdn.jsdelivr.net/npm/, unpkg.com, cdn.tailwindcss.com, code.jquery.com; always an exact pinned version at least two weeks old. Stylesheets only from Google Fonts. Everything else inline.
- Page size ≤ 16MB, including `data:` URIs.
- Colors as tokens on `:root`, with dark-mode overrides under `@media (prefers-color-scheme: dark)` guarded by `:root:not([data-theme="light"])` and again under `:root[data-theme="dark"]`. Give `body` an explicit background.
- Must work at phone width: 16px side gutter, no horizontal page scroll.
- `localStorage`/`sessionStorage` are per-viewer and can throw or be empty: wrap every access in try/catch and render correctly without it. Use them only for conveniences (settings, a local best score). For state that must be shared or persist reliably (leaderboards, shared daily seeds), load the `artifact-capabilities` skill and use a capability instead.
- Publish with the Artifact tool using the game's `index.html` as `file_path`. Republish the same path to update the same URL; pass `icon` on first publish only.

## Game code guidelines

- Seeded PRNG (e.g. mulberry32) for all gameplay randomness; show the seed and allow entering one.
- Separate game state/logic from rendering, so logic can be tested headlessly (e.g. with Playwright, which is preinstalled in cloud sessions).
- Input: keyboard and touch (on-screen buttons or swipe). Pause on `visibilitychange`.
- Render with Canvas or DOM grid; prefer turn-based loops over `requestAnimationFrame` physics unless the mechanic needs it.
- Permadeath is the default: a run ends in a summary screen with a one-tap restart.

## Workflow

- Verify a game loads without console errors before publishing (Playwright + Chromium).
- Commit per game; message format `<slug>: <what changed>`.
- Record the published artifact URL in the `README.md` table.
