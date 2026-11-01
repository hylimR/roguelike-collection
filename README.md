# Roguelike Collection

A collection of proof-of-concept roguelike games. Each game is a self-contained, single-file HTML page, published as a [Claude Artifact](https://claude.ai) by default.

## Layout

```
games/
  <slug>/
    index.html    # the whole game: markup, styles, script
    README.md     # optional: one-paragraph pitch, controls, what the POC tests
```

One folder per game, kebab-case slug (e.g. `games/dungeon-dash/`). Keep a game's assets inline unless it needs more than one file; multi-file games publish extra files alongside `index.html`.

A game can instead be a Godot 4.6 project (`games/<slug>/project.godot`, GDScript only) when asked for. Those run in Godot, not as artifacts, and keep a headless test under `tests/`.

## Adding a game

1. Create `games/<slug>/index.html`.
2. Play it locally by opening the file in a browser; no build step.
3. Publish it as an artifact (see `CLAUDE.md` for the constraints that apply).
4. Add a row to the table below, with the artifact link once published.

## Games

| Game | Slug | Core idea | Status | Artifact |
|------|------|-----------|--------|----------|
| [Konbini Empire](games/konbini-empire/) | `konbini-empire` | Stock a konbini day by day, pay weekly rent, grow into a supermarket and a three-store chain, build the flagship. Isometric busy-street view; rearrange and decorate the shop. Pixel art by Codex. | playable | Godot 4.6 project (no artifact) |

Status: `idea` → `poc` → `playable` → `shelved`.

## Principles

- **POC first.** Each game proves one mechanic or twist; cut everything else.
- **No build, no backend.** Vanilla JS (or a pinned CDN library) in one HTML file.
- **Playable on a phone.** Touch controls alongside keyboard.
- **Seedable runs.** Randomness goes through a seeded PRNG so runs are reproducible and bugs are replayable.
