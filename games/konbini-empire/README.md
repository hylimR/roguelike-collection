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

Each applicant has a trait, such as speedy, slacker, night owl or charming. Every level-up and every closed rival or milestone offers a card: skills, the five abilities (Flyer Blitz, Time Sale, Counter Campaign, Influencer Visit, Express Truck), and legendary rewards. Expansions for each store add product lines (coffee, karaage and oden at the counter; beer, ice cream and daily goods on more floor; bento, cup noodles and manga on the most floor), knock through a wall, or buy a neon sign, second register, vending machine, gacha corner, ATM, bench, camera or delivery bike.

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
- Beyond the built-up edge, homes thin out into fields and woods, and the bay opens to the south.

Each store is played on its own street, carved into the city on its lot:

- your shop as a cutaway, with a till on the counter, shelf boards, glass-door fridges, and potted plants and a sandwich board at the door;
- the rival's shop along the street: its shelves behind mullioned glass, a fascia in the chain's stripes, air-conditioning units on the roof;
- neighbours in that district's own building style;
- a crossing whose lights the pedestrians wait for, speckled asphalt with manhole covers, yellow tactile paving down both sidewalks, and utility poles with sagging wires along the far side;
- Tokyo carrying on around it: the side streets and avenues that cross the set run on through it, opening a gap in its sidewalks and its rows of buildings, and the city's own buildings stay wherever the set doesn't build. Only city buildings on the street, in the open ground in front of it, or covering your shop are cleared, along with expressway decks (and their pillars) that would hide the street.

Every box in the scene is shaded per face (top brightest, the street face next), so counters, shelves and buildings read as solid.

The light follows the clock: a pink dawn, plain daylight, a golden hour before the evening rush, a violet dusk, then night. After dark the street goes dark blue while windows and neon signs light up, street lamps and vending machines throw pools of light, the rival's glass front glows, and your shop stays brightly lit with everyone inside it. The camera starts close on your shop with the rival's sign in frame. Press M for the city map, which shows your branches and their rivals and highlights the lots on offer when you look for a new store.

The HUD floats over the street in rounded cream bubbles, island-life style, and leaves the street the whole screen:

- a big white clock with the day in a pill, with pause, speed, sound and seed buttons under it;
- money, level, rating and bills tags along the top;
- a small store card in the top-right corner that is only as tall as its content: district, rent and wages, the rival's takings, and one key per product showing its stock bar and restock price (click to restock);
- store tabs, round ability keys, a speech bubble for news and a dock of colored app keys (Staff, Expand, Store, City) along the bottom.

The store card hides on the city map. The game fills any window shape: a wider (ultrawide) or taller window shows more of the street instead of black bars, and the 3D scene renders at the screen's own resolution.

Sound follows the street on screen: the door chime as customers walk in, coins on every sale, a scanner beep that climbs with your ring-up combo, a whoosh and a poof for chased-off threats, an alert before each attack. Level-ups, closed rivals and the nightly report get their own jingles. The music changes with the hour, like a clock radio: a morning, an afternoon, an evening and a night piece, crossfading as the day goes on.

**Run:** open `project.godot` in Godot 4.6 and press Play.

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

**Art:** sprites and backgrounds were generated by Codex image_gen on a magenta key, then cut and downsampled into `art/`. Building facades and shop fittings are drawn in code. Sound effects and music were generated with ElevenLabs (Sound Effects and Eleven Music) from text prompts. Fonts: Nunito, with Noto Sans as the fallback (both SIL Open Font License; Nunito's licence is in `fonts/OFL-Nunito.txt`).
