# Konbini Empire

Run konbini across Tokyo in real time, each one in a street fight with the rival chain next door. Every day runs from 06:00 to midnight, and two and a half minutes at 1x. Passers-by walk the street, and those after something you stock pick your shop or the rival's by how appealing each is. Customers take an item off the shelf, queue at the till, and pay when a cashier, or you, rings them up. Every sale also hits the rival's takings (its HP). Each rival customer heals it. Drive it to zero and it closes for good; two days later a tougher chain moves in.

The rival fights back. It warns a few seconds ahead, then launches an attack:

- a flyer promoter or a mascot parade that poaches your customers;
- trash bags dumped at your door;
- a price war;
- fake reviews;
- shoplifters;
- a blackout that stops the tills;
- a hostile takeover by three suits who each grab 15% of your cash at the door.

Click a threat to chase it off. Click the till to ring up a waiting customer; fast ring-ups build a combo that multiplies XP. Click a shelf to restock it. Customers who find an empty shelf, a full queue or a slow till leave angry, and your rating drops.

Spend what you earn on staff:

- cashiers;
- stock clerks, who never touch tonight's bills;
- cleaners for spills and trash;
- a guard;
- a promoter on the sidewalk.

Each applicant has a trait, such as speedy, slacker, night owl or charming. The staff panel groups crew and applicants under colored role tags with open slots, and colors each trait by whether it works faster, slower or has a special effect. Every level-up and every closed rival or milestone offers a card: skills, the five abilities (Flyer Blitz, Time Sale, Counter Campaign, Influencer Visit, Express Truck), and legendary rewards. Expansions for each store add product lines (coffee, karaage and oden at the counter; beer, ice cream and daily goods on more floor; bento, cup noodles and manga on the most floor), knock through a wall, or buy a neon sign, second register, vending machine, gacha corner, ATM, bench, camera or delivery bike.

New stores open on Tokyo lots. Each lot's neighbourhood type sets its foot traffic, rent, what the locals buy and how tough a rival it draws. Each lot also has a quirk: corner lot, bargain lease, haunted unit, tourist hotspot, bus stop or school. Rent rises the longer you hold a store. Rent and wages for the whole chain are due at midnight. If you're short, the bank forecloses your weakest store; with nothing left to take, the run ends. Street events (matsuri, heatwave, cold snap, TV feature, roadworks, health inspection) change a store's day. The heatwave's haze and the cold snap's snow show on the street.

The city is 48 real neighbourhoods laid out roughly where they are:

- Shinjuku, Shibuya, Ikebukuro, Ueno and Tokyo Station as Yamanote Line hubs;
- Ginza and Azabu for luxury;
- Roppongi and Ebisu for nightlife;
- Akihabara for otaku;
- Asakusa and Odaiba for tourists;
- Sugamo's grandmothers and Tsukiji's early workers;
- the Imperial Palace in the middle.

It's drawn like a city builder:

- Blocks split into side streets that meet in T-junctions, and curved avenues cut across them.
- The elevated Shuto expressway rings the palace and runs out along the radial avenues, with ramps down to the street.
- The Rainbow Bridge crosses to Odaiba, and Yamanote trains circle on their viaduct.
- Every block is packed with 3D buildings drawn by a pixel facade shader: glass towers at the hubs, neon in the nightlife districts, wooden machiya in the old town, gable-roofed houses in the suburbs.
- Open ground between buildings is paved in slabs, or fine gravel in the leafy districts, so a station plaza reads as a square rather than bare ground.
- Beyond the built-up edge, homes thin out into fields and woods, and the bay opens to the south.

Each store is played on its own street, carved into the city on its lot:

- your shop as a cutaway, with a till on the counter, shelf boards and glass-door fridges faced up with packs and bottles in each product's colors that thin out as its stock runs down, and potted plants and a sandwich board at the door; the part of the unit you haven't knocked through yet stands vacant beside it, shutter down under a bare fascia with a to-let notice on it; a parked car with wheel stops in its car park and a pole sign in your stripes that stays lit after dark;
- the rival's shop along the street: its shelves behind mullioned glass, a fascia in the chain's stripes, and a roof inside a parapet with a stair hatch, a walkway, air-conditioning units on plinths piped into one trunk, and skylights that glow after dark;
- neighbours in that district's own building style, the shotengai ones with a shopfront under a scalloped awning: stocked shelves behind mullioned glass and a glazed door, every one lit after dark;
- a crossing whose lights the pedestrians wait for (where a side road meets it, its light stands on that road's corner), speckled asphalt with manhole covers and white edge lines, zebra crossings over each side road, yellow tactile paving down both sidewalks, utility poles with sagging wires along the far side, and tall street lamps whose arms reach out over the road, their heads lighting up after dark;
- soft shadows under people, cars, trees and street furniture, and a dark seam where each building meets the sidewalk;
- Tokyo carrying on around it: the side streets and avenues that cross the set run on through it, opening a gap in its sidewalks and its rows of buildings, and the city's own buildings stay wherever the set doesn't build. City buildings in front of the street are cut down to knee height, like a diorama's cut-away, showing their walls' section round a dim floor, so the street stays in view over a block that still reads as city. Only city buildings on the street itself or where the set builds its own are cleared, along with expressway decks (and their pillars) that would hide the street. Where the set reaches over water (the bay, a canal, the Sumida) it stands on made ground, its street with a strip either side and the plots of your shop and the rival, so a waterfront store gets a quay and a river runs up to the street and on past it; the neighbours keep out of the water.

Every box in the scene is shaded per face (top brightest, the street face next), so counters, shelves and buildings read as solid.

The light follows the clock: a pink dawn, plain daylight, a golden hour before the evening rush (walls facing the low sun glow amber while the shaded sides go cool), a violet dusk, then night. After dark the street goes dark blue while windows and neon signs light up, street lamps and vending machines throw pools of light, the rival's glass front glows, and your shop stays brightly lit with everyone inside it. The camera starts close on your shop with the rival's sign in frame. Press M for the city map, which shows your branches and their rivals and highlights the lots on offer when you look for a new store; district names sit on dark rounded plates, the Yamanote hubs a size larger, so they read over day roofs and night windows alike.

The HUD floats over the street in rounded cream bubbles, island-life style, and leaves the street the whole screen:

- a big white clock with the day in a pill, with pause, speed, sound and seed buttons under it;
- money, level, rating and bills tags along the top;
- a small store card in the top-right corner that is only as tall as its content: district, rent and wages, the rival's takings, and one key per product showing its stock bar and restock price (click to restock), a full shelf a pale mint tile marked Full in green;
- store tabs, round ability keys, a speech bubble for news and a dock of colored app keys (Staff, Expand, Store, City) along the bottom; a key that can't be used fades to a flat, paler shade of its own color.

The store card hides on the city map. The game fills any window shape: a wider (ultrawide) or taller window shows more of the street instead of black bars, and the 3D scene renders at the screen's own resolution.

Sound follows the street on screen: the door chime as customers walk in, coins on every sale, a scanner beep that climbs with your ring-up combo, a whoosh and a poof for chased-off threats, an alert before each attack. Level-ups, closed rivals and the nightly report get their own jingles. The music changes with the hour, like a clock radio: a morning, an afternoon, an evening and a night piece, crossfading as the day goes on.

**Run:** open `project.godot` in Godot 4.6 and press Play.

**Web build:** `python tools/web.py [path to godot]` exports a single-threaded Web build to `build/web/` (ignored by git). Its sound is mixed by the engine (`audio/general/default_playback_type.web` is Stream), because Godot's default web sample playback came out silent here. It needs the standard Godot editor; the .NET build can't export to the Web. When the web export template isn't installed, it fetches just that file out of Godot's template archive. `node tools/shot.mjs` serves the build to headless Chromium (Playwright, WebGL through SwiftShader, a few frames a second) and runs steps in order: `eval:` GDScript run against the main node, `wait:`, `key:`, `click:` and `shot:` (a screenshot). It loads the page with `?dev`, which is the only time the game exposes that hook. Use it to check the game's look on a machine with no GPU or display:

```bash
node tools/shot.mjs "key:Space" "eval:main.sim.time = 125.0" "wait:3" "shot:/tmp/night.png" "eval:main.toggle_city()" "wait:4" "shot:/tmp/map.png"
```

**Artifact:** `python tools/web.py [path to godot] --artifact` makes a release build in `build/artifact/` to publish as a Claude Artifact, with `tools/artifact.html` as the page. Artifacts serve only web file types, at up to 15 MB each, so the engine ships gzipped as `index.wasm` (the page unpacks it as it loads) and the game pack as `index.pck.wasm`. Publish `index.html` with `index.js`, the two `index.audio*.worklet.js` files, `index.wasm` and `index.pck.wasm`.

**Controls:** mouse and keyboard (on a touch screen, taps act as clicks).

- **Click:** threats, the till and shelves. Drag to pan, scroll to zoom.
- **Space:** pause.
- **F:** speed (1x, 2x, 3x).
- **R:** ring up.
- **1-5:** abilities.
- **P:** open a pending card.
- **S:** staff.
- **G:** expand this store.
- **N:** new store.
- **M:** city map; right-drag turns it.
- **V:** sound: on, music off, muted.
- **Tab:** next store.
- **Esc:** close.

Cards, the staff panel and the nightly report pause the game. The seed button starts a new run, optionally with a seed.

**Check:** `godot --headless --path games/konbini-empire --script res://tests/balance.gd`. It checks:

- the random generator against reference vectors;
- the XP, expansion, reroll, store-price, rent-age and rival-HP curves;
- appeal values and listing prices;
- the starting state;
- that a rejected action leaves the seed alone.

A bot then plays eight days on two seeds, asserting invariants every step and that a seed replays identically.

`godot --headless --path games/konbini-empire --script res://tests/audio.gd` checks that every sound the game plays exists and loads, and that every hour of the day has music.

**Code:**

- `sim.gd` holds the rules: no nodes, and positions in a street frame of 1 m units, with your door at x = -5.4 and the rival's at x = 14.
- `city.gd` lays out Tokyo; it is built once and cached.
- `store_view.gd` draws the city and each branch's street set, and turns clicks into actions.
- `main.gd` holds the HUD, the cards and the real-time loop.
- `audio.gd` plays the effects and the time-of-day music on their own buses.

**Art:** sprites and backgrounds were generated by Codex image_gen on a magenta key, then cut and downsampled into `art/`. Building facades and shop fittings are drawn in code. Sound effects and music were generated with ElevenLabs (Sound Effects and Eleven Music) from text prompts. Fonts: Nunito, with Noto Sans and a three-glyph subset of Noto Sans Math (★ ♪ ▾) as fallbacks, so the web build needs no system fonts (all SIL Open Font License; Nunito's licence is in `fonts/OFL-Nunito.txt`).
