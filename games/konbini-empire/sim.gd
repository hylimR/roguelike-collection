extends RefCounted
## Konbini Empire rules: a real-time street battle at every branch, each branch on a Tokyo lot. Ported from the
## Battle Konbini mechanics spec. No nodes, no rendering, so tests/balance.gd runs it headless.
## Positions are in a street frame: x along the street, shops on the north side (negative z), 1 unit = 1 m; the view
## maps that frame onto the branch's lot. "Local" points are inside your shop, relative to ORIGIN.

const City := preload("res://city.gd")

# ---------- balance ----------
const DAY_LENGTH := 150.0
const MAX_STEP := 0.1
const SPAWN_PER_SEC := 1.25
const MAX_PEDS := 120
const SHOPPER_CHANCE := 0.74
const NONE_WEIGHT := 4.0
const ALLEY_CHANCE := 0.35
const OPENING_CROWD := 24
const INSIDE_SPEED := 1.35
const BASE_PATIENCE := 17.0
const CHECKOUT_TIME := 2.1
const MAX_QUEUE := [7, 4]
const START_CASH := 2200
const START_RATING := 3.0
const RATING_HAPPY := 0.014
const RATING_FAST := 0.006
const BASE_APPEAL := 10.0
const COMBO_WINDOW := 3.5
const STREAK_WINDOW := 3.0
const SIGNAL_PERIOD := 22.0
const SIGNAL_WALK := 13.0
const STOCKER_INTERVAL := 1.2
const STOCKER_THRESHOLD := 0.35
const STOCKER_WORK := 1.4
const ATM_FEE := 30
const DELIVERY_INTERVAL := 22.0
const LOW_STOCK := 0.3  # UI only
const MAX_STORES := 6
const MAX_SPILLS := 6
const SPILL_DRAIN := 0.0025
const STAFF_WALK := 2.4
const GUARD_WALK := 3.2
const REACH := 0.9
const BRANCH_GAP := 80.0  # a new branch's street keeps clear of the others'

# ---------- street frame ----------
const ORIGIN := Vector2(-10.0, -11.7)  # your shop's centre; local = world - ORIGIN
const SPAWN_X := 44.0
const ALLEYS := [-27.0, 4.6, 30.5]
const CROSS_X := 2.0
const DOOR := Vector2(-5.4, -6.6)  # outside your door
const DOOR_OUT := Vector2(4.6, 5.1)  # local
const DOOR_IN := Vector2(4.6, 3.6)
const ROWS := [-2.3, 0.6, 3.0]
const ZONE_LEFT := [0.0, -0.2, -3.0, -6.5]  # left wall by store size
const VENDING_X := -17.6
const GACHA_X := -18.9
const FLYER_STAND := Vector2(-2.8, -5.9)
const PROMOTER_HOME := Vector2(-9.8, -5.7)
const REVIEW_AT := Vector2(-7.4, -6.5)
const MASCOT_TURN := -11.4
const TRASH_SPOTS := [Vector2(2.4, 5.5), Vector2(3.4, 5.8), Vector2(1.5, 5.85)]  # local
const BREAKER_AT := Vector2(6.2, -4.38)  # on the back wall behind the counter
const CAT_HOME := Vector2(1.9, 4.15)  # by the window, between the queue tail's places on screen
const COUNTER_END := Vector2(5.7, 2.4)
const AISLE_COLUMN := 2.75  # the cross aisle: 0.4 off the fixture ends, 0.75 clear of the queue along the counter
const AISLE_CORNER := Vector2(AISLE_COLUMN, 3.0)
const STAFF_HOMES := {"stocker": [Vector2(5.7, 2.2), Vector2(5.7, -3.3)], "cleaner": [Vector2(2.7, 4.15), Vector2(1.1, 4.15)], "guard": [Vector2(3.5, 4.15), Vector2(0.3, 4.15)], "promoter": [Vector2(0.2, 6.0)]}
const REGISTERS := [
	{"pos": Vector2(4.5, 0.3), "clerk": Vector2(5.35, 0.3), "queue": [Vector2(3.5, 0.3), Vector2(3.5, 1.15), Vector2(3.5, 2.0), Vector2(3.35, 3.6), Vector2(2.55, 3.6), Vector2(1.75, 3.6), Vector2(0.95, 3.6)]},
	{"pos": Vector2(4.5, -1.6), "clerk": Vector2(5.35, -1.6), "queue": [Vector2(3.5, -1.6), Vector2(3.5, -2.45), Vector2(2.7, -3.1), Vector2(1.9, -3.1)]},
]
# pick = where a customer stands; counter lines have none
const SLOTS := {
	"fridgeC": {"pos": Vector2(1.2, -3.95), "pick": Vector2(1.2, -2.3)},
	"shelfC": {"pos": Vector2(1.2, -0.55), "pick": Vector2(1.2, 0.6)},
	"frontA": {"pos": Vector2(1.2, 1.85), "pick": Vector2(1.2, 3.0)},
	"counterA": {"pos": Vector2(4.5, 1.25)},
	"counterB": {"pos": Vector2(4.5, -0.6)},
	"counterC": {"pos": Vector2(4.5, -2.7)},
	"fridgeB": {"pos": Vector2(-1.6, -3.95), "pick": Vector2(-1.6, -2.3)},
	"shelfB": {"pos": Vector2(-1.6, -0.55), "pick": Vector2(-1.6, 0.6)},
	"island": {"pos": Vector2(-1.6, 1.85), "pick": Vector2(-1.6, 3.0)},
	"fridgeA": {"pos": Vector2(-4.4, -3.95), "pick": Vector2(-4.4, -2.3)},
	"shelfA": {"pos": Vector2(-4.4, -0.55), "pick": Vector2(-4.4, 0.6)},
	"rack": {"pos": Vector2(-4.4, 4.05), "pick": Vector2(-4.4, 3.0)},
}

# ---------- content (source order matters: weighted draws walk it) ----------
# icon: [sheet, frame] in art/
const PRODUCTS := {
	"drink": {"name": "Drinks", "price": 140, "cost": 35, "cap": 12, "slot": "fridgeC", "zone": 1, "icon": ["products", 4]},
	"onigiri": {"name": "Onigiri", "price": 160, "cost": 40, "cap": 10, "slot": "shelfC", "zone": 1, "icon": ["products", 0]},
	"snack": {"name": "Snacks", "price": 180, "cost": 45, "cap": 12, "slot": "frontA", "zone": 1, "icon": ["products", 6]},
	"coffee": {"name": "Hot Coffee", "price": 150, "cost": 20, "cap": 20, "slot": "counterA", "zone": 1, "counter": true, "icon": ["products", 3]},
	"bento": {"name": "Bento", "price": 520, "cost": 160, "cap": 6, "slot": "fridgeA", "zone": 3, "icon": ["products", 1]},
	"chicken": {"name": "Karaage", "price": 230, "cost": 55, "cap": 8, "slot": "counterB", "zone": 1, "counter": true, "icon": ["perks", 5]},
	"oden": {"name": "Oden", "price": 300, "cost": 75, "cap": 10, "slot": "counterC", "zone": 1, "counter": true, "icon": ["products", 24]},
	"icecream": {"name": "Ice Cream", "price": 250, "cost": 70, "cap": 10, "slot": "island", "zone": 2, "icon": ["products", 9]},
	"beer": {"name": "Beer & Chūhai", "price": 290, "cost": 80, "cap": 12, "slot": "fridgeB", "zone": 2, "icon": ["products", 22]},
	"manga": {"name": "Manga & Mags", "price": 420, "cost": 130, "cap": 8, "slot": "rack", "zone": 3, "icon": ["decor", 8]},
	"noodle": {"name": "Cup Noodles", "price": 220, "cost": 55, "cap": 12, "slot": "shelfA", "zone": 3, "icon": ["products", 8]},
	"daily": {"name": "Daily Goods", "price": 360, "cost": 105, "cap": 8, "slot": "shelfB", "zone": 2, "icon": ["products", 20]},
}
const START_LINES := ["drink", "onigiri", "snack"]

const SCHEDULE := [
	{"name": "Morning Rush", "from": 6.0, "to": 10.0, "rush": true, "traffic": 1.5, "wants": [["coffee", 30], ["onigiri", 24], ["drink", 18], ["bento", 4], ["snack", 4], ["manga", 8], ["daily", 6]]},
	{"name": "Late Morning", "from": 10.0, "to": 11.5, "rush": false, "traffic": 0.8, "wants": [["drink", 20], ["snack", 16], ["coffee", 14], ["daily", 16], ["manga", 12], ["onigiri", 12], ["icecream", 6]]},
	{"name": "Lunch Rush", "from": 11.5, "to": 14.0, "rush": true, "traffic": 1.6, "wants": [["bento", 30], ["onigiri", 20], ["drink", 18], ["chicken", 16], ["noodle", 8], ["coffee", 6], ["snack", 6]]},
	{"name": "Afternoon", "from": 14.0, "to": 17.0, "rush": false, "traffic": 0.85, "wants": [["snack", 22], ["drink", 18], ["icecream", 18], ["coffee", 12], ["manga", 12], ["daily", 12], ["chicken", 6]]},
	{"name": "Evening Rush", "from": 17.0, "to": 20.0, "rush": true, "traffic": 1.5, "wants": [["chicken", 20], ["bento", 20], ["beer", 16], ["oden", 14], ["drink", 10], ["snack", 10], ["daily", 10], ["noodle", 6]]},
	{"name": "Night", "from": 20.0, "to": 23.0, "rush": false, "traffic": 0.9, "wants": [["beer", 24], ["oden", 16], ["icecream", 14], ["snack", 14], ["noodle", 14], ["manga", 12], ["chicken", 10], ["drink", 10]]},
	{"name": "Last Orders", "from": 23.0, "to": 24.01, "rush": false, "traffic": 0.3, "wants": [["beer", 24], ["snack", 20], ["noodle", 16], ["icecream", 16], ["oden", 14], ["drink", 14], ["manga", 12]]},
]

# Street profiles; every Tokyo neighbourhood type maps onto one (PROFILE_OF).
const DISTRICTS := {
	"sakura": {"name": "Shōtengai", "traffic": 1.0, "rent": 1300, "tier": 0, "cost": 1.0, "demand": {}},
	"campus": {"name": "Student street", "traffic": 1.15, "rent": 1700, "tier": 0, "cost": 1.1, "demand": {"manga": 1.8, "coffee": 1.4, "noodle": 1.6, "snack": 1.3}},
	"onsen": {"name": "Visitor lane", "traffic": 1.1, "rent": 1900, "tier": 1, "cost": 1.25, "demand": {"beer": 1.8, "icecream": 1.6, "drink": 1.4, "oden": 1.5}},
	"ekimae": {"name": "Station front", "traffic": 1.35, "rent": 2600, "tier": 1, "cost": 1.45, "demand": {"coffee": 1.5, "onigiri": 1.4, "bento": 1.3}},
	"neon": {"name": "Neon downtown", "traffic": 1.75, "rent": 4200, "tier": 2, "cost": 1.9, "demand": {"beer": 1.4, "chicken": 1.4, "manga": 1.2}},
}
const PROFILE_OF := {"hub": "ekimae", "office": "ekimae", "nightlife": "neon", "luxury": "neon", "university": "campus", "youth": "campus", "otaku": "campus", "tourist": "onsen", "market": "onsen", "homes": "sakura", "oldtown": "sakura", "park": "sakura", "palace": "sakura"}

const QUIRKS := {
	"plain": {"name": "Standard lease", "w": 4},
	"corner": {"name": "Corner lot", "w": 2, "appeal": 1.15, "rent": 1.15},
	"cheap": {"name": "Bargain lease", "w": 2, "rent": 0.7, "appeal": 0.9},
	"haunted": {"name": "Haunted unit", "w": 1, "rent": 0.5, "rating": 2.0, "patience": 0.85},
	"tourist": {"name": "Tourist hotspot", "w": 2, "price": 1.15, "rent": 1.1},
	"busStop": {"name": "Bus stop outside", "w": 2, "traffic": 1.25},
	"school": {"name": "Next to a school", "w": 2, "demand": {"snack": 2.0, "icecream": 2.0, "manga": 2.0}},
	"office": {"name": "Office tower above", "w": 2, "demand": {"coffee": 2.0, "bento": 2.0}},
}

# front = storefront frame in art/storefronts.png
const RIVALS := {
	"tanuki": {"name": "Tanuki Mart", "tier": 0, "hp": 3600, "appeal": 10.0, "heal": 6.0, "escalation": 0.10, "interval": [24.0, 32.0], "first": 28.0, "door": 14.0, "width": 13.0, "color": "e04a3a", "front": 4,
		"sells": ["drink", "onigiri", "snack", "coffee", "bento", "manga"], "attacks": ["flyer", "trash", "priceWar", "mascot"]},
	"kappa": {"name": "Kappa Corner", "tier": 0, "hp": 4400, "appeal": 10.5, "heal": 6.0, "escalation": 0.10, "interval": [23.0, 31.0], "first": 26.0, "door": 14.0, "width": 13.0, "color": "3fae49", "front": 6,
		"sells": ["drink", "onigiri", "snack", "coffee", "noodle", "icecream"], "attacks": ["flyer", "trash", "priceWar", "review"]},
	"usagi": {"name": "Usagi Express", "tier": 1, "hp": 12000, "appeal": 12.0, "heal": 8.0, "escalation": 0.11, "interval": [21.0, 29.0], "first": 22.0, "door": 14.0, "width": 13.0, "color": "2f7fd6", "front": 2,
		"sells": ["drink", "onigiri", "snack", "coffee", "bento", "icecream", "daily", "manga"], "attacks": ["flyer", "trash", "priceWar", "review", "mascot"]},
	"kitsune": {"name": "Kitsune 24", "tier": 1, "hp": 20000, "appeal": 13.0, "heal": 10.0, "escalation": 0.12, "interval": [19.0, 27.0], "first": 20.0, "door": 14.0, "width": 13.0, "color": "9b4dca", "front": 8,
		"sells": ["drink", "onigiri", "snack", "coffee", "bento", "chicken", "beer", "daily", "icecream", "noodle"], "attacks": ["flyer", "trash", "priceWar", "review", "shoplifter", "mascot"]},
	"oni": {"name": "Oni Discount", "tier": 2, "hp": 45000, "appeal": 14.5, "heal": 11.0, "escalation": 0.12, "interval": [17.0, 25.0], "first": 18.0, "door": 14.0, "width": 13.0, "color": "c2410c", "front": 5,
		"sells": ["drink", "onigiri", "snack", "coffee", "bento", "chicken", "oden", "beer", "manga", "noodle", "daily"], "attacks": ["flyer", "trash", "priceWar", "review", "shoplifter", "blackout", "mascot"]},
	"mega": {"name": "MEGAMART∞", "tier": 3, "hp": 85000, "appeal": 16.0, "heal": 13.0, "escalation": 0.12, "interval": [15.0, 22.0], "first": 16.0, "door": 16.0, "width": 15.0, "color": "4a4f63", "front": 9,
		"sells": ["drink", "onigiri", "snack", "coffee", "bento", "chicken", "oden", "icecream", "beer", "manga", "noodle", "daily"], "attacks": ["flyer", "priceWar", "review", "shoplifter", "blackout", "takeover", "mascot", "trash"]},
}
const ATTACKS := {
	"flyer": {"name": "Flyer Promoter", "clicks": 3},
	"trash": {"name": "Trash Dump", "clicks": 1},
	"priceWar": {"name": "Price War", "clicks": 0},
	"mascot": {"name": "Mascot Parade", "clicks": 5},
	"review": {"name": "Fake Review", "clicks": 1},
	"shoplifter": {"name": "Shoplifter", "clicks": 2},
	"blackout": {"name": "Blackout", "clicks": 3},
	"takeover": {"name": "Hostile Takeover", "clicks": 3},
}
const RIVAL_THREATS := ["flyer", "trash", "mascot", "review", "shoplifter", "breaker", "suit"]

const ROLES := {
	"cashier": {"name": "Cashier", "wage": 260, "max": 0},
	"stocker": {"name": "Stock Clerk", "wage": 300, "max": 2},
	"cleaner": {"name": "Cleaner", "wage": 220, "max": 2},
	"guard": {"name": "Security Guard", "wage": 380, "max": 1},
	"promoter": {"name": "Promoter", "wage": 280, "max": 1},
}
const TRAITS := {
	"steady": {"name": "Steady", "w": 5, "speed": 1.0, "wage": 1.0},
	"diligent": {"name": "Diligent", "w": 3, "speed": 1.25, "wage": 1.15},
	"speedy": {"name": "Speedy", "w": 2, "speed": 1.5, "wage": 1.35},
	"veteran": {"name": "Veteran", "w": 1, "speed": 1.8, "wage": 1.7},
	"rookie": {"name": "Rookie", "w": 3, "speed": 0.75, "wage": 0.65},
	"slacker": {"name": "Slacker", "w": 2, "speed": 1.3, "wage": 0.7, "desc": "takes breaks"},
	"nightOwl": {"name": "Night Owl", "w": 2, "speed": 1.0, "wage": 1.0, "desc": "x1.8 after 19:00"},
	"earlyBird": {"name": "Early Bird", "w": 2, "speed": 1.0, "wage": 1.0, "desc": "x1.8 before 11:00"},
	"charming": {"name": "Charming", "w": 2, "speed": 1.0, "wage": 1.15, "desc": "+5% appeal"},
}
const STAFF_NAMES := ["Hana", "Mei", "Yuki", "Sora", "Ren", "Aoi", "Haru", "Kaito", "Riku", "Yui", "Saki", "Daichi", "Kenji", "Emi", "Taro", "Nana", "Shota", "Mio", "Kota", "Rina", "Yuto", "Ami", "Sho", "Kana", "Hiro", "Momo", "Takumi", "Rin", "Jun", "Asuka", "Kei", "Mika"]

const ABILITIES := {
	"flyer": {"name": "Flyer Blitz", "cd": [24.0, 21.0, 18.0], "radius": [13.0, 17.0, 21.0]},
	"timeSale": {"name": "Time Sale", "cd": [45.0, 40.0, 35.0], "dur": [12.0, 16.0, 20.0], "mult": [2.0, 2.5, 3.0]},
	"counter": {"name": "Counter Campaign", "cd": [55.0, 48.0, 41.0], "pct": [0.05, 0.07, 0.09]},
	"influencer": {"name": "Influencer Visit", "cd": [80.0, 70.0, 60.0], "fans": [6, 9, 12]},
	"truck": {"name": "Express Truck", "cd": [40.0, 34.0, 28.0], "discount": [0.6, 0.5, 0.4]},
}

const EVENTS := {
	"festival": {"name": "Summer Matsuri", "w": 2, "traffic": 1.5, "from": 17.0, "demand": {"beer": 2.0, "chicken": 2.0, "icecream": 2.0}, "desc": "Crowds from 17:00; beer, karaage and ice cream x2."},
	"heatwave": {"name": "Heatwave", "w": 2, "demand": {"drink": 3.0, "icecream": 3.0}, "desc": "Drinks and ice cream x3."},
	"coldSnap": {"name": "Cold Snap", "w": 2, "demand": {"oden": 2.5, "coffee": 2.5, "noodle": 2.5}, "desc": "Oden, coffee and cup noodles x2.5."},
	"tv": {"name": "TV Feature", "w": 1, "appeal": 1.3, "desc": "Appeal x1.3 all day."},
	"roadworks": {"name": "Roadworks", "w": 1, "traffic": 0.7, "desc": "30% fewer passers-by."},
	"inspector": {"name": "Health Inspection", "w": 2, "desc": "At noon: clean floor +0.2★, else ¥400 per mess."},
}

const MILESTONES := {
	"stores2": {"name": "Second Store"}, "staff5": {"name": "Team of Five"}, "day10": {"name": "Ten Days Open"},
	"stores3": {"name": "Local Chain"}, "sales100k": {"name": "Six Figures"}, "rivals3": {"name": "Street Fighter"},
	"staff12": {"name": "Payroll Pro"}, "day25": {"name": "Neighbourhood Fixture"}, "stores5": {"name": "Konbini Empire"},
	"sales1m": {"name": "Konbini King"}, "day50": {"name": "Institution"},
}

const DEFAULT_MODS := {
	"appeal": 1.0, "price": 1.0, "checkout": 1.0, "xp": 1.0, "damage": 1.0, "restock": 1.0, "patience": 1.0,
	"rating_gain": 1.0, "rating_loss": 1.0, "impulse": 1.0, "rent": 1.0, "wage": 1.0, "staff_speed": 1.0, "spill": 1.0,
	"upsell": 0.0, "lucky": 0.0, "combo_cap": 10.0, "combo_step": 0.1, "thick_skin": 0.0, "night": 0.0, "morning": 0.0,
	"interest": 0.0, "hot_streak": 0.0, "golden_hour": 0.0, "loyalty": 0.0,
}
const RARITY := {"common": 60.0, "rare": 28.0, "epic": 10.0, "legendary": 3.0}

# pool: skill (level-ups), expansion (bought per store), reward (rivals closed, milestones)
const UPGRADES := {
	"charm": {"pool": "skill", "name": "Charming Smile", "rarity": "common", "max": 5, "add": {"appeal": 0.12}, "desc": "Appeal +12% at every store."},
	"premium": {"pool": "skill", "name": "Premium Branding", "rarity": "rare", "max": 3, "add": {"price": 0.10}, "desc": "Prices +10%."},
	"swift": {"pool": "skill", "name": "Swift Hands", "rarity": "common", "max": 4, "add": {"checkout": 0.25}, "desc": "Checkout 25% faster."},
	"learner": {"pool": "skill", "name": "Fast Learner", "rarity": "common", "max": 3, "add": {"xp": 0.15}, "desc": "XP +15%."},
	"spirit": {"pool": "skill", "name": "Competitive Spirit", "rarity": "common", "max": 5, "add": {"damage": 0.18}, "desc": "Damage to rivals +18%."},
	"bulk": {"pool": "skill", "name": "Bulk Buyer", "rarity": "common", "max": 3, "mul": {"restock": 0.88}, "desc": "Restocking 12% cheaper."},
	"bow": {"pool": "skill", "name": "Polite Bow", "rarity": "common", "max": 3, "add": {"patience": 0.35, "rating_gain": 0.2}, "desc": "Customers wait 35% longer; rating gains +20%."},
	"impulse": {"pool": "skill", "name": "Irasshaimase!", "rarity": "common", "max": 2, "add": {"impulse": 0.6}, "desc": "Passers-by drop in on impulse 60% more."},
	"maneki": {"pool": "skill", "name": "Maneki-neko", "rarity": "epic", "max": 1, "add": {"lucky": 0.06}, "facility": "maneki", "desc": "6% of sales are lucky: x5, at every store."},
	"nightOwl": {"pool": "skill", "name": "Night Owl", "rarity": "rare", "max": 1, "add": {"night": 0.4}, "desc": "Sales after 19:00 +40%."},
	"earlyBird": {"pool": "skill", "name": "Early Bird", "rarity": "rare", "max": 1, "add": {"morning": 0.4}, "desc": "Sales before 11:00 +40%."},
	"upsell": {"pool": "skill", "name": "Upsell", "rarity": "rare", "max": 2, "add": {"upsell": 0.2}, "desc": "20% of sales upsell: x1.8."},
	"pointCard": {"pool": "skill", "name": "Point Card", "rarity": "rare", "max": 1, "add": {"loyalty": 0.25}, "desc": "A quarter of customers come back as regulars."},
	"comboMaster": {"pool": "skill", "name": "Combo Master", "rarity": "rare", "max": 2, "add": {"combo_cap": 6.0, "combo_step": 0.05}, "desc": "Combo cap +6, combo XP +5% a step."},
	"thickSkin": {"pool": "skill", "name": "Thick Skin", "rarity": "common", "max": 2, "add": {"thick_skin": 1.0}, "desc": "Rival threats take a click less; fake reviews last 3 s longer."},
	"hotStreak": {"pool": "skill", "name": "Hot Streak", "rarity": "rare", "max": 2, "add": {"hot_streak": 0.04}, "desc": "Each sale in a streak adds 4% damage (up to 10)."},
	"negotiator": {"pool": "skill", "name": "Rent Negotiator", "rarity": "rare", "max": 2, "mul": {"rent": 0.85}, "desc": "Rent -15%."},
	"hr": {"pool": "skill", "name": "HR Department", "rarity": "rare", "max": 2, "mul": {"wage": 0.88}, "desc": "Wages -12%."},
	"teamSpirit": {"pool": "skill", "name": "Team Spirit", "rarity": "common", "max": 3, "add": {"staff_speed": 0.15}, "desc": "Staff work 15% faster."},
	"spotless": {"pool": "skill", "name": "Non-slip Floors", "rarity": "common", "max": 1, "mul": {"spill": 0.6}, "desc": "40% fewer spills."},
	"investor": {"pool": "skill", "name": "Investor", "rarity": "rare", "max": 1, "add": {"interest": 0.06}, "desc": "6% interest on cash each night (max ¥2,000)."},
	"goldenHour": {"pool": "skill", "name": "Golden Hour", "rarity": "legendary", "max": 1, "add": {"golden_hour": 1.0}, "desc": "Rush hours: damage x2."},
	"omotenashi": {"pool": "skill", "name": "Omotenashi", "rarity": "epic", "max": 1, "mul": {"rating_loss": 0.5}, "desc": "Rating losses halved; +0.5★ at every store now."},
	"cat": {"pool": "skill", "name": "Store Cat", "rarity": "epic", "max": 1, "facility": "cat", "desc": "A cat chases rival threats off this store."},
	"ab_flyer": {"pool": "skill", "name": "Flyer Blitz", "rarity": "common", "max": 3, "ability": "flyer", "desc": "Ability: pull in walkers near your door."},
	"ab_timeSale": {"pool": "skill", "name": "Time Sale", "rarity": "rare", "max": 3, "ability": "timeSale", "desc": "Ability: appeal x2 or more for a while, at 85% prices."},
	"ab_counter": {"pool": "skill", "name": "Counter Campaign", "rarity": "rare", "max": 3, "ability": "counter", "desc": "Ability: hit the rival for 5% of its HP and end its price war."},
	"ab_influencer": {"pool": "skill", "name": "Influencer Visit", "rarity": "epic", "max": 3, "ability": "influencer", "desc": "Ability: a crowd of fans walks in."},
	"ab_truck": {"pool": "skill", "name": "Express Truck", "rarity": "common", "max": 3, "ability": "truck", "desc": "Ability: restock everything at 60% cost."},
	"p_coffee": {"pool": "expansion", "name": "Hot Coffee", "rarity": "common", "max": 1, "product": "coffee", "desc": "New line at the counter."},
	"p_bento": {"pool": "expansion", "name": "Bento", "rarity": "common", "max": 1, "product": "bento", "desc": "New line (needs a big floor)."},
	"p_chicken": {"pool": "expansion", "name": "Karaage", "rarity": "common", "max": 1, "product": "chicken", "desc": "New line at the counter."},
	"p_icecream": {"pool": "expansion", "name": "Ice Cream", "rarity": "common", "max": 1, "product": "icecream", "desc": "New line (needs more floor)."},
	"p_daily": {"pool": "expansion", "name": "Daily Goods", "rarity": "common", "max": 1, "product": "daily", "desc": "New line (needs more floor)."},
	"p_oden": {"pool": "expansion", "name": "Oden", "rarity": "rare", "max": 1, "product": "oden", "desc": "New line at the counter."},
	"p_beer": {"pool": "expansion", "name": "Beer & Chūhai", "rarity": "rare", "max": 1, "product": "beer", "desc": "New line (needs more floor)."},
	"p_manga": {"pool": "expansion", "name": "Manga & Mags", "rarity": "rare", "max": 1, "product": "manga", "desc": "New line (needs a big floor)."},
	"p_noodle": {"pool": "expansion", "name": "Cup Noodles", "rarity": "common", "max": 1, "product": "noodle", "desc": "New line (needs a big floor)."},
	"floor": {"pool": "expansion", "name": "Knock Through a Wall", "rarity": "common", "max": 2, "type": "growth", "store_add": {"appeal": 0.1}, "desc": "More floor for new lines, +10% appeal, higher rent."},
	"neon": {"pool": "expansion", "name": "Neon Sign", "rarity": "rare", "max": 1, "facility": "neon", "desc": "Appeal +25%, up to +50% at night."},
	"register2": {"pool": "expansion", "name": "Second Register", "rarity": "rare", "max": 1, "facility": "register2", "desc": "A second till and room for a second cashier."},
	"bigShelves": {"pool": "expansion", "name": "Big Shelves", "rarity": "common", "max": 2, "store_add": {"capacity": 0.5}, "desc": "Every line holds 50% more."},
	"vending": {"pool": "expansion", "name": "Vending Machine", "rarity": "common", "max": 1, "facility": "vending", "desc": "Passers-by buy drinks outside."},
	"gacha": {"pool": "expansion", "name": "Gacha Corner", "rarity": "rare", "max": 1, "facility": "gacha", "desc": "Passers-by play for ¥300."},
	"atm": {"pool": "expansion", "name": "ATM Corner", "rarity": "common", "max": 1, "facility": "atm", "desc": "Appeal +8%, +¥30 on every sale."},
	"bench": {"pool": "expansion", "name": "Bench & Planters", "rarity": "common", "max": 1, "facility": "bench", "store_add": {"rating_gain": 0.1}, "desc": "+0.3★ now, rating gains +10% here."},
	"camera": {"pool": "expansion", "name": "Security Camera", "rarity": "rare", "max": 1, "facility": "camera", "desc": "Blocks half of fake reviews, catches shoplifters."},
	"delivery": {"pool": "expansion", "name": "Delivery Bike", "rarity": "epic", "max": 1, "facility": "delivery", "desc": "A double sale every 22 s."},
	"r_franchise": {"pool": "reward", "name": "Franchise Fame", "rarity": "legendary", "max": 1, "add": {"appeal": 0.3, "price": 0.2}, "desc": "Appeal +30%, prices +20%."},
	"r_warchest": {"pool": "reward", "name": "War Chest", "rarity": "legendary", "max": 3, "cash": 4000, "desc": "¥4,000 now."},
	"r_killer": {"pool": "reward", "name": "Killer Instinct", "rarity": "legendary", "max": 2, "add": {"damage": 0.45}, "desc": "Damage +45%."},
	"r_express": {"pool": "reward", "name": "Shinkansen Service", "rarity": "legendary", "max": 2, "add": {"checkout": 0.6, "patience": 0.3}, "desc": "Checkout +60%, patience +30%."},
	"r_scholar": {"pool": "reward", "name": "MBA Manager", "rarity": "legendary", "max": 2, "add": {"xp": 0.35}, "desc": "XP +35%; the next expansion is cheaper at every store."},
	"r_hq": {"pool": "reward", "name": "Head Office", "rarity": "legendary", "max": 2, "mul": {"wage": 0.8}, "desc": "Wages -20%."},
	"r_logistics": {"pool": "reward", "name": "Central Warehouse", "rarity": "legendary", "max": 2, "mul": {"restock": 0.85}, "desc": "Restocking 15% cheaper."},
	"r_brand": {"pool": "reward", "name": "National Ad Campaign", "rarity": "legendary", "max": 3, "add": {"appeal": 0.15}, "desc": "Appeal +15%."},
	"r_academy": {"pool": "reward", "name": "Staff Academy", "rarity": "legendary", "max": 2, "add": {"staff_speed": 0.25}, "desc": "Staff 25% faster."},
}


## mulberry32: the one source of gameplay randomness, carried in `rng_seed` between steps.
class Rng:
	const MASK := 0xFFFFFFFF
	var s := 0

	func _init(seed_: int) -> void:
		s = seed_ & MASK

	## Math.imul for uint32 operands, without overflowing 64-bit ints.
	static func imul(a: int, b: int) -> int:
		return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK

	func next() -> float:
		s = (s + 0x6d2b79f5) & MASK
		var r := imul(s ^ (s >> 15), s | 1)
		r = (r ^ ((r + imul(r ^ (r >> 7), r | 61)) & MASK)) & MASK
		return float((r ^ (r >> 14)) & MASK) / 4294967296.0

	func range_f(a: float, b: float) -> float:
		return a + next() * (b - a)

	func int_in(a: int, b: int) -> int:
		return a + floori(next() * (b - a + 1))

	func chance(p: float) -> bool:
		return next() < p

	func pick(list: Array) -> Variant:
		return list[floori(next() * list.size())]

	## [[value, weight], ...]; null when no weight is positive.
	func weighted(entries: Array) -> Variant:
		var total := 0.0
		for e in entries:
			total += maxf(0.0, e[1])
		if total <= 0.0:
			return null
		var r := next() * total
		var last = null
		for e in entries:
			if e[1] <= 0.0:
				continue
			last = e[0]
			r -= e[1]
			if r < 0.0:
				return e[0]
		return last


var rng_seed := 0
var run_seed := 0
var seed_text := ""
var rng := Rng.new(0)
var phase := "intro"  # intro | playing | choice | gameOver
var day := 1
var time := 0.0
var total_time := 0.0
var next_id := 1000
var player: Dictionary
var branches: Array = []
var active := 0
var next_branch_id := 2
var choice = null  # the open pick card: {source, options, ...}
var pending: Array = []  # queued level-up and reward picks
var milestones := {}
var listing_offer = null
var report = null
var summary = null
var run_stats: Dictionary
var events: Array = []  # drained by the view and UI
var lots: Array = []  # Tokyo shop lots: {block, x0, front, use: free | store}
var districts: Array = []  # City districts
var cur := -1  # branch being worked on: tags its events


static func rnd(x: float) -> int:
	return floori(x + 0.5)


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


static func xp_for_level(level: int) -> int:
	return rnd(70.0 * pow(1.3, level - 1))


func mods() -> Dictionary:
	return player.mods


func emit(type: String, data := {}) -> void:
	data.type = type
	if cur >= 0 and cur < branches.size():
		data.branch = branches[cur].id
	events.append(data)


# ---------- run setup ----------

func start(seed_str: String) -> void:
	seed_text = seed_str
	create_run(hash(seed_str))


func create_run(s: int) -> void:
	rng_seed = s & Rng.MASK
	run_seed = rng_seed
	phase = "intro"
	day = 1
	time = 0.0
	total_time = 0.0
	next_id = 1000
	player = {"cash": START_CASH, "level": 1, "xp": 0.0, "xp_next": xp_for_level(1), "mods": DEFAULT_MODS.duplicate(), "taken": {}, "abilities": {}, "rerolls": 0}
	active = 0
	next_branch_id = 2
	choice = null
	pending = []
	milestones = {}
	listing_offer = null
	report = null
	summary = null
	run_stats = {"revenue": 0, "customers": 0, "rivals_defeated": 0, "days": 0, "threats_repelled": 0, "stores_opened": 1, "peak_stores": 1, "foreclosed": 0}
	events = []
	cur = -1
	branches = []
	var C := City.get_city()
	districts = C.districts
	lots = []
	for L in C.lots:
		lots.append({"block": L.block, "x0": L.x0, "front": L.front, "use": "free"})
	var homes := range(lots.size()).filter(func(i): return profile_of(i) == "sakura")
	var li: int = Rng.new(rng_seed ^ 0x51ed270b).pick(homes)
	var setup := Rng.new(rng_seed ^ 0x2545f491)
	branches = [new_branch(1, {"district": "sakura", "quirk": "plain", "rival": "tanuki", "tier": 0, "cost": 7000, "lot": li}, setup, true)]
	rng = Rng.new(rng_seed)


func profile_of(li: int) -> String:
	return PROFILE_OF[districts[lots[li].block].type]


func new_branch(id: int, L: Dictionary, r: Rng, first: bool) -> Dictionary:
	var q: Dictionary = QUIRKS[L.quirk]
	var st := {
		"size": 1, "products": {}, "facilities": [],
		"registers": [{"id": 0, "queue": [], "progress": 0.0, "active": true}, {"id": 1, "queue": [], "progress": 0.0, "active": false}],
		"rating": q.get("rating", START_RATING), "mods": {"appeal": 1.0, "capacity": 1.0, "rating_gain": 1.0},
		"expansions": 0, "offer": null, "taken": {}, "crew": [], "applicants": [],
	}
	for pid in START_LINES:
		add_line(st, pid)
	var name: String = "Hana" if first else r.pick(STAFF_NAMES)
	st.crew = [member(1 if first else take_id(), "cashier", "steady", name, r)]
	st.applicants = roll_applicants(r, 100 if first else -1)
	var tokyo: String = districts[lots[L.lot].block].name
	var label := tokyo
	var n := 2
	while branches.any(func(b): return b.name == label):
		label = "%s %d-chōme" % [tokyo, n]
		n += 1
	lots[L.lot].use = "store"
	return {
		"id": id, "name": label, "district": L.district, "quirk": L.quirk, "opened": day, "cost": L.cost,
		"rival_gen": 0, "event": null, "populated": false, "store": st, "rival": create_rival(L.rival, L.tier),
		"agents": [], "threats": [], "staff": [], "spawn_acc": 0.0, "timers": {"delivery": DELIVERY_INTERVAL},
		"effects": {"time_sale": 0.0}, "combo": {"count": 0, "timer": 0.0}, "streak": {"count": 0, "timer": 0.0},
		"regulars": 0, "day_stats": zero_stats(), "lot": L.lot,
	}


func zero_stats() -> Dictionary:
	return {"revenue": 0, "customers": 0, "lost": 0, "restock": 0, "passive": 0, "rival_damage": 0.0, "rival_customers": 0, "fines": 0}


func take_id() -> int:
	next_id += 1
	return next_id - 1


func add_line(st: Dictionary, pid: String) -> void:
	var cap := rnd(PRODUCTS[pid].cap * st.mods.capacity)
	st.products[pid] = {"stock": cap, "capacity": cap}


func member(id: int, role: String, trait_id: String, name: String, r: Rng) -> Dictionary:
	var wage := rnd(ROLES[role].wage * TRAITS[trait_id].wage * r.range_f(0.9, 1.1) / 10.0) * 10
	return {"id": id, "role": role, "name": name, "trait_id": trait_id, "wage": wage}


## Two per role, names unique within the batch. first_id < 0: ids from the shared counter.
func roll_applicants(r: Rng, first_id: int) -> Array:
	var out := []
	var used := []
	var traits := TRAITS.keys().map(func(k): return [k, TRAITS[k].w])
	for role in ROLES:
		for k in 2:
			var pick_trait: String = r.weighted(traits)
			var name: String = r.pick(STAFF_NAMES.filter(func(n): return not used.has(n)))
			used.append(name)
			var id := first_id + out.size() if first_id >= 0 else take_id()
			out.append(member(id, role, pick_trait, name, r))
	return out


func create_rival(id: String, tier: int) -> Dictionary:
	var def: Dictionary = RIVALS[id]
	tier = maxi(tier, def.tier)
	var hp := rnd(def.hp * pow(1.6, tier - def.tier))
	return {"id": id, "tier": tier, "x": def.door, "width": def.width, "hp": float(hp), "max_hp": float(hp), "attack_timer": def.first,
		"telegraph": "", "price_war": 0.0, "defeated": false, "last_attack": "", "days": 1, "closed_days": 0}


# ---------- clock ----------

func hour() -> float:
	return 6.0 + minf(time, DAY_LENGTH) / DAY_LENGTH * 18.0


static func band(h: float) -> Dictionary:
	for b in SCHEDULE:
		if b.from <= h and h < b.to:
			return b
	return SCHEDULE[-1]


static func smoothstep_(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func night_factor(h: float) -> float:
	return maxf(1.0 - smoothstep_(5.5, 7.5, h), smoothstep_(17.5, 20.0, h))


## [walk light on, flashing, cars amber]
func lights() -> Array:
	var t := fmod(total_time, SIGNAL_PERIOD)
	return [t >= SIGNAL_WALK, SIGNAL_PERIOD - t < 2.5 and t >= SIGNAL_WALK, t >= 11.0 and t < SIGNAL_WALK]


func crossing_open() -> bool:
	var t := fmod(total_time, SIGNAL_PERIOD)
	return t >= SIGNAL_WALK and SIGNAL_PERIOD - t >= 2.5


# ---------- branch helpers ----------

func owns(b: Dictionary, pid) -> bool:
	return pid != null and b.store.products.has(pid)


func event_def(b: Dictionary) -> Dictionary:
	return EVENTS[b.event.id] if b.event != null else {}


func local_traffic(b: Dictionary, h: float) -> float:
	var t: float = DISTRICTS[b.district].traffic * QUIRKS[b.quirk].get("traffic", 1.0)
	var e := event_def(b)
	if e.has("traffic") and h >= e.get("from", 0.0):
		t *= e.traffic
	return t


func local_wants(b: Dictionary, wants: Array) -> Array:
	var d: Dictionary = DISTRICTS[b.district].demand
	var q: Dictionary = QUIRKS[b.quirk].get("demand", {})
	var e: Dictionary = event_def(b).get("demand", {})
	return wants.map(func(w): return [w[0], w[1] * d.get(w[0], 1.0) * q.get(w[0], 1.0) * e.get(w[0], 1.0)])


func count_threats(b: Dictionary, type: String) -> int:
	var n := 0
	for t in b.threats:
		if t.type == type:
			n += 1
	return n


func has_threat(b: Dictionary, type: String, include_fleeing := true) -> bool:
	for t in b.threats:
		if t.type == type and (include_fleeing or not t.fleeing):
			return true
	return false


func charming(b: Dictionary) -> int:
	return b.store.crew.filter(func(m): return m.trait_id == "charming").size()


func player_appeal(b: Dictionary) -> float:
	var st: Dictionary = b.store
	var m := mods()
	var v: float = BASE_APPEAL * (0.45 + st.rating / 4.5) * m.appeal * st.mods.appeal * QUIRKS[b.quirk].get("appeal", 1.0) * event_def(b).get("appeal", 1.0)
	v *= 1.0 + 0.05 * charming(b)
	if b.effects.time_sale > 0.0:
		v *= ABILITIES.timeSale.mult[ability_level("timeSale") - 1]
	v *= pow(0.82, count_threats(b, "trash")) * pow(0.9, count_threats(b, "spill"))
	if has_threat(b, "breaker"):
		v *= 0.4
	if st.facilities.has("neon"):
		v *= 1.25 + 0.25 * night_factor(hour())
	if st.facilities.has("atm"):
		v *= 1.08
	return v


func rival_age(r: Dictionary) -> int:
	return mini(r.days, 8) - 1


func tier_scale(r: Dictionary) -> float:
	return pow(1.6, maxi(0, r.tier - RIVALS[r.id].tier))


func rival_appeal(b: Dictionary) -> float:
	var r: Dictionary = b.rival
	if r.defeated:
		return 0.0
	var def: Dictionary = RIVALS[r.id]
	return def.appeal * (1.0 + def.escalation * rival_age(r)) * pow(tier_scale(r), 0.35) * (1.75 if r.price_war > 0.0 else 1.0) * (0.65 + 0.35 * r.hp / r.max_hp)


func choose_target(b: Dictionary, want) -> String:
	if want == null:
		return "none"
	var opts := [["none", NONE_WEIGHT]]
	if owns(b, want):
		opts.append(["player", player_appeal(b)])
	if not b.rival.defeated and RIVALS[b.rival.id].sells.has(want):
		opts.append(["rival", rival_appeal(b)])
	return rng.weighted(opts)


func ability_level(id: String) -> int:
	return player.abilities.get(id, {}).get("level", 0)


func adjust_rating(b: Dictionary, delta: float) -> void:
	var st: Dictionary = b.store
	var scaled: float = delta * mods().rating_gain * st.mods.rating_gain if delta >= 0.0 else delta * mods().rating_loss
	st.rating = clampf(st.rating + scaled, 0.5, 5.0)


func work_rate(m: Dictionary, h: float) -> float:
	var r: float = TRAITS[m.trait_id].speed * mods().staff_speed
	if m.trait_id == "nightOwl" and h >= 19.0:
		r *= 1.8
	if m.trait_id == "earlyBird" and h < 11.0:
		r *= 1.8
	return r


func rent(b: Dictionary) -> int:
	var size_f: float = 1.0 + 0.3 * (b.store.size - 1)
	var age := minf(2.5, pow(1.05, maxi(0, day - b.opened)))
	return rnd(DISTRICTS[b.district].rent * QUIRKS[b.quirk].get("rent", 1.0) * size_f * age * mods().rent)


func wages(b: Dictionary) -> int:
	var n := 0
	for m in b.store.crew:
		n += rnd(m.wage * mods().wage)
	return n


func bills_due() -> int:
	var n := 0
	for b in branches:
		n += rent(b) + wages(b)
	return n


static func expansion_cost(st: Dictionary) -> int:
	return rnd(900.0 * pow(1.38, st.expansions))


func reroll_cost() -> int:
	return rnd(200.0 * pow(1.6, player.rerolls))


func store_cost() -> int:
	return rnd(7000.0 * pow(1.7, run_stats.stores_opened - 1))


func role_cap(st: Dictionary, role: String) -> int:
	if role == "cashier":
		return st.registers.filter(func(r): return r.active).size()
	return ROLES[role].max


## Cashiers in hiring order serve the active registers in id order.
func cashier_of(b: Dictionary, reg_id: int):
	var cashiers: Array = b.store.crew.filter(func(m): return m.role == "cashier")
	var k := 0
	for r in b.store.registers:
		if not r.active:
			continue
		if r.id == reg_id:
			return cashiers[k] if k < cashiers.size() else null
		k += 1
	return null


func body_of(b: Dictionary, crew_id: int):
	for s in b.staff:
		if s.crew_id == crew_id:
			return s
	return null


func on_break(b: Dictionary, m: Dictionary) -> bool:
	var s = body_of(b, m.id)
	return s != null and s.break_t > 0.0


func agent_by_id(b: Dictionary, id: int):
	for a in b.agents:
		if a.id == id:
			return a
	return null


func threat_by_id(b: Dictionary, id: int):
	for t in b.threats:
		if t.id == id:
			return t
	return null


func remove_threat(b: Dictionary, id: int) -> void:
	b.threats = b.threats.filter(func(t): return t.id != id)


# ---------- paths ----------

static func lane_z(north: bool, t: float) -> float:
	return -6.3 + 1.8 * t if north else 4.5 + 1.8 * t


static func side_of(z: float) -> String:
	return "north" if z < -3.5 else ("south" if z > 3.5 else "road")


static func world(l: Vector2) -> Vector2:
	return l + ORIGIN


static func local_of(o: Dictionary) -> Vector2:
	return Vector2(o.x, o.z) - ORIGIN


static func nearest_row(z: float) -> float:
	var best: float = ROWS[0]
	for r in ROWS:
		if absf(z - r) < absf(z - best):
			best = r
	return best


## Through the aisles: snap to the nearest row, change rows at the cheaper column. Local in, world out.
static func aisle(from: Vector2, to: Vector2, size: int) -> Array:
	var r0 := nearest_row(from.y)
	var r1 := nearest_row(to.y)
	var pts := [Vector2(from.x, r0)]
	if r0 != r1:
		var c := AISLE_COLUMN
		if size >= 3 and absf(from.x + 6.0) + absf(to.x + 6.0) < absf(from.x - c) + absf(to.x - c):
			c = -6.0
		pts.append(Vector2(c, r0))
		pts.append(Vector2(c, r1))
	pts.append(to)
	return pts.map(func(p): return p + ORIGIN)


## Walking path to a door from the street: south-siders cross at the lights, alley and road walkers step onto the
## north lane first.
func path_to(a: Dictionary, door: Vector2) -> void:
	var pts := []
	a.hold = -1
	var nz := lane_z(true, a.lane)
	var side := side_of(a.z)
	if side == "south":
		var cx: float = CROSS_X + a.cross_j
		pts.append(Vector2(cx, lane_z(false, a.lane)))
		pts.append(Vector2(cx, 3.7))
		a.hold = 1
		pts.append(Vector2(cx, nz))
	elif side == "road" or a.z < -7.2:
		pts.append(Vector2(a.x, nz))
	pts.append(Vector2(door.x, nz))
	pts.append(door)
	a.path = pts
	a.pi = 0


func exit_path(a: Dictionary) -> void:
	var north: bool = a.z < 0.0
	var z := lane_z(north, a.lane)
	a.path = [Vector2(a.x, z), Vector2(a.dir * SPAWN_X, z)]
	a.pi = 0
	a.hold = -1


func set_target(b: Dictionary, a: Dictionary, target: String) -> void:
	a.target = target
	a.state = "walk"
	if target == "player":
		path_to(a, DOOR)
	elif target == "rival":
		path_to(a, Vector2(b.rival.x, -6.6))
	else:
		exit_path(a)


## Pedestrian walking: leftover movement carries on to the next waypoint. Waits at the curb (`hold`) for the lights.
func follow(a: Dictionary, dist: float) -> bool:
	var path: Array = a.path
	var moved := false
	while a.pi < path.size():
		if a.hold >= 0 and a.pi == a.hold + 1:
			if not crossing_open():
				break
			a.hold = -1
		if dist <= 0.0:
			break
		var p: Vector2 = path[a.pi]
		var dx: float = p.x - a.x
		var dz: float = p.y - a.z
		var l := sqrt(dx * dx + dz * dz)
		if l > 0.0001:
			a.heading = atan2(dz, dx)
			moved = true
		if l <= dist:
			a.x = p.x
			a.z = p.y
			dist -= l
			a.pi += 1
		else:
			a.x += dx / l * dist
			a.z += dz / l * dist
			dist = 0.0
	a.moving = moved
	return a.pi >= path.size()


## Threats and staff: one waypoint at a time, no carried movement.
static func follow_once(o: Dictionary, dist: float) -> bool:
	var path: Array = o.path
	if o.pi >= path.size():
		o.moving = false
		return true
	var p: Vector2 = path[o.pi]
	var d := p - Vector2(o.x, o.z)
	var l := d.length()
	o.moving = l > 0.0001
	if l > 0.0001:
		o.heading = atan2(d.y, d.x)
	if l <= dist:
		o.x = p.x
		o.z = p.y
		o.pi += 1
	else:
		o.x += d.x / l * dist
		o.z += d.y / l * dist
	return o.pi >= path.size()


## Staff go round the counter end and the aisle corner, and use the door. Local in, world out.
static func staff_route(from: Vector2, to: Vector2, size: int) -> Array:
	var f_in := from.y < 4.5
	var t_in := to.y < 4.5
	var f_back := f_in and from.x > 5.0
	var t_back := t_in and to.x > 5.0
	var pts := []
	var at := from
	if f_back and not t_back:
		pts += [COUNTER_END, AISLE_CORNER]
		at = AISLE_CORNER
	if f_in and not t_in:
		pts += _local(aisle(at, DOOR_IN, size)) + [DOOR_OUT, to]
	elif not f_in and t_in:
		pts += [DOOR_OUT, DOOR_IN]
		if t_back:
			pts += _local(aisle(DOOR_IN, AISLE_CORNER, size)) + [COUNTER_END, to]
		else:
			pts += _local(aisle(DOOR_IN, to, size))
	elif f_in and t_in:
		if t_back and not f_back:
			pts += _local(aisle(at, AISLE_CORNER, size)) + [COUNTER_END, to]
		elif t_back:
			pts.append(to)
		else:
			pts += _local(aisle(at, to, size))
	else:
		pts.append(to)
	var out := []
	for p in pts:
		if p.distance_to(from) > 0.02 or not out.is_empty():
			out.append(p + ORIGIN)
	return out


static func _local(pts: Array) -> Array:
	return pts.map(func(p): return p - ORIGIN)


# ---------- simulation ----------

func tick(dt: float) -> void:
	while dt > 1e-6 and phase == "playing":
		var h := minf(dt, MAX_STEP)
		step(h)
		dt -= h


func step(dt: float) -> void:
	rng = Rng.new(rng_seed)
	time += dt
	total_time += dt
	for id in player.abilities:
		player.abilities[id].cd = maxf(0.0, player.abilities[id].cd - dt)
	for i in branches.size():
		cur = i
		var b: Dictionary = branches[i]
		if not b.populated:
			prepopulate(b)
			b.populated = true
		b.effects.time_sale = maxf(0.0, b.effects.time_sale - dt)
		for k in ["combo", "streak"]:
			var c: Dictionary = b[k]
			if c.timer > 0.0:
				c.timer -= dt
			else:
				c.count = 0
				c.timer = 0.0
		spawn_peds(b, dt)
		update_peds(b, dt)
		update_registers(b, dt)
		update_staff(b, dt)
		update_delivery(b, dt)
		update_rival(b, dt)
		update_threats(b, dt)
		update_street(b, dt)
		check_defeat(b)
	cur = -1
	check_level_ups()
	check_milestones()
	if time >= DAY_LENGTH:
		end_day()
	rng_seed = rng.s


func prepopulate(b: Dictionary) -> void:
	for k in rnd(OPENING_CROWD * local_traffic(b, hour())):
		spawn_agent(b, {"x": rng.range_f(-40.0, 40.0)})


func spawn_peds(b: Dictionary, dt: float) -> void:
	var h := hour()
	b.spawn_acc += SPAWN_PER_SEC * band(h).traffic * local_traffic(b, h) * dt
	while b.spawn_acc >= 1.0:
		b.spawn_acc -= 1.0
		if b.agents.size() >= MAX_PEDS:
			continue
		if b.regulars > 0 and rng.chance(0.3):
			b.regulars -= 1
			spawn_agent(b, {"kind": "regular", "want": rng.pick(b.store.products.keys()), "target": "player"})
		else:
			spawn_agent(b, {})


func spawn_agent(b: Dictionary, o: Dictionary) -> Dictionary:
	var dir := 0.0
	if o.has("dir"):
		dir = o.dir
	else:
		dir = 1.0 if rng.chance(0.5) else -1.0
	var alley := false
	if o.has("alley"):
		alley = o.alley
	elif not o.has("x"):
		alley = rng.chance(ALLEY_CHANCE)
	var north := true
	if not alley:
		north = o.north if o.has("north") else rng.chance(0.55)
	var lane := rng.next()
	var x := 0.0
	var z := 0.0
	if alley:
		x = rng.pick(ALLEYS) + rng.range_f(-0.5, 0.5)
		z = -10.2
	else:
		x = o.x if o.has("x") else -dir * SPAWN_X
		z = lane_z(north, lane)
	var shopper: bool = o.has("want") or rng.chance(SHOPPER_CHANCE)
	var want = null
	if o.has("want"):
		want = o.want
	elif shopper:
		want = rng.weighted(local_wants(b, band(hour()).wants))
	var a := {
		"id": take_id(), "kind": o.get("kind", "ped"), "x": x, "z": z, "heading": 0.0 if dir > 0.0 else PI, "moving": false,
		"speed": rng.range_f(1.3, 1.9), "lane": lane, "cross_j": rng.range_f(-1.0, 1.0), "dir": dir, "want": want,
		"target": "none", "state": "walk", "path": [], "pi": 0, "hold": -1, "timer": 0.0, "wait": 0.0, "patience": 0.0,
		"look": 0, "mood": "", "mood_timer": 0.0, "bag": "", "impulse": false, "vended": false, "register": -1,
		"at_head": false, "inside": false,
	}
	a.patience = BASE_PATIENCE * mods().patience * QUIRKS[b.quirk].get("patience", 1.0) * rng.range_f(0.8, 1.25)
	a.look = rng.int_in(0, 2147483646)
	set_target(b, a, o.target if o.has("target") else choose_target(b, want))
	b.agents.append(a)
	return a


func update_peds(b: Dictionary, dt: float) -> void:
	var keep := []
	for a in b.agents.duplicate():
		if step_agent(b, a, dt):
			keep.append(a)
	b.agents = keep


## One pedestrian; false once it has left the street.
func step_agent(b: Dictionary, a: Dictionary, dt: float) -> bool:
	if a.mood_timer > 0.0:
		a.mood_timer -= dt
		if a.mood_timer <= 0.0:
			a.mood = ""
	match a.state:
		"walk":
			var done := follow(a, a.speed * dt)
			if try_impulse(b, a):
				return true
			try_vending(b, a)
			if done:
				match a.target:
					"player":
						enter_store(b, a)
					"rival":
						a.state = "inRival"
						a.timer = rng.range_f(3.0, 6.0)
						a.moving = false
					_:
						return false
		"shopping":
			if follow(a, INSIDE_SPEED * dt):
				a.state = "browse"
				a.moving = false
				a.timer = rng.range_f(0.8, 1.5)
		"browse":
			a.timer -= dt
			if a.timer <= 0.0:
				take_item(b, a)
		"queue":
			step_queue(b, a, dt)
		"leaving":
			if follow(a, INSIDE_SPEED * dt):
				a.inside = false
				a.impulse = true
				set_target(b, a, "none")
		"inRival":
			a.timer -= dt
			if a.timer <= 0.0:
				var r: Dictionary = b.rival
				if not r.defeated:
					var heal: float = RIVALS[r.id].heal * tier_scale(r) * (1.0 + 0.1 * rival_age(r))
					r.hp = minf(r.max_hp, r.hp + heal)
					b.day_stats.rival_customers += 1
					emit("rivalSale", {"heal": heal, "x": a.x, "z": a.z})
					a.bag = "rival"
				set_target(b, a, "none")
	return true


func try_impulse(b: Dictionary, a: Dictionary) -> bool:
	if a.target != "none" or a.impulse or a.want == null or a.z >= -3.5 or absf(a.x - DOOR.x) > 5.0 or not owns(b, a.want):
		return false
	a.impulse = true
	var p := minf(0.6, 0.12 * mods().impulse * player_appeal(b) / 10.0)
	if rng.chance(p):
		set_target(b, a, "player")
		emit("impulse", {"x": a.x, "z": a.z})
		return true
	return false


func try_vending(b: Dictionary, a: Dictionary) -> void:
	if a.vended or a.z >= -3.5:
		return
	var f: Array = b.store.facilities
	var value := 0.0
	if f.has("vending") and absf(a.x - VENDING_X) < 0.5:
		a.vended = true
		value = 130.0 if rng.chance(0.10) else 0.0
	elif f.has("gacha") and absf(a.x - GACHA_X) < 0.5:
		a.vended = true
		value = 300.0 if rng.chance(0.07) else 0.0
	if value > 0.0:
		var v: float = value * mods().price
		apply_sale(b, {"revenue": rnd(v), "damage": v / 10.0 * mods().damage, "xp": v / 12.0 / 2.0, "lucky": false, "upsell": false, "product": "vending" if value < 200.0 else "gacha"}, true, a.x, a.z, -1)


func enter_store(b: Dictionary, a: Dictionary) -> void:
	emit("enter", {"x": a.x, "z": a.z})
	if PRODUCTS[a.want].get("counter", false):
		take_item(b, a)
		return
	a.inside = true
	a.state = "shopping"
	a.path = [world(DOOR_IN)] + aisle(DOOR_IN, SLOTS[PRODUCTS[a.want].slot].pick, b.store.size)
	a.pi = 0


func take_item(b: Dictionary, a: Dictionary) -> void:
	var p = b.store.products.get(a.want)
	if p == null or p.stock <= 0:
		adjust_rating(b, -0.07)
		b.day_stats.lost += 1
		emit("stockout", {"product": a.want})
		leave_angry(b, a, "stock")
		return
	p.stock -= 1
	join_queue(b, a)


func join_queue(b: Dictionary, a: Dictionary) -> void:
	var best = null
	var best_staffed := false
	for r in b.store.registers:
		if not r.active or r.queue.size() >= MAX_QUEUE[r.id]:
			continue
		var staffed: bool = cashier_of(b, r.id) != null
		if best == null or (staffed and not best_staffed) or (staffed == best_staffed and r.queue.size() < best.queue.size()):
			best = r
			best_staffed = staffed
	if best == null:
		leave_angry(b, a, "queue")
		adjust_rating(b, -0.06)
		return
	best.queue.append(a.id)
	a.register = best.id
	a.state = "queue"
	a.wait = 0.0
	a.at_head = false
	var spot: Vector2 = REGISTERS[best.id].queue[best.queue.size() - 1]
	if a.inside:
		a.path = aisle(local_of(a), spot, b.store.size)
	else:
		a.inside = true
		a.path = [world(DOOR_IN)] + aisle(DOOR_IN, spot, b.store.size)
	a.pi = 0


func step_queue(b: Dictionary, a: Dictionary, dt: float) -> void:
	a.wait += dt
	var reg: Dictionary = b.store.registers[a.register]
	var idx: int = reg.queue.find(a.id)
	if a.wait > a.patience:
		if idx == 0:
			reg.progress = 0.0
		reg.queue.erase(a.id)
		b.day_stats.lost += 1
		adjust_rating(b, -0.06)
		leave_angry(b, a, "wait")
		return
	var spot := world(REGISTERS[a.register].queue[idx])
	if a.pi >= a.path.size():
		if Vector2(a.x, a.z).distance_to(spot) > 0.001:
			a.path = [spot]
			a.pi = 0
	else:
		a.path[-1] = spot
	a.at_head = follow(a, INSIDE_SPEED * dt) and idx == 0


func leave_angry(b: Dictionary, a: Dictionary, reason: String) -> void:
	a.mood = "angry"
	a.mood_timer = 3.0
	a.impulse = true
	a.register = -1
	a.at_head = false
	emit("angry", {"reason": reason, "x": a.x, "z": a.z, "id": a.id})
	if local_of(a).y > 4.4:
		a.inside = false
		set_target(b, a, "none")
	else:
		a.state = "leaving"
		a.path = aisle(local_of(a), DOOR_IN, b.store.size) + [world(DOOR_OUT)]
		a.pi = 0


func update_registers(b: Dictionary, dt: float) -> void:
	if has_threat(b, "breaker"):
		return
	for reg in b.store.registers.duplicate():
		if not reg.active or reg.queue.is_empty():
			continue
		var m = cashier_of(b, reg.id)
		var rate := 0.0
		if m != null and not on_break(b, m):
			rate = mods().checkout * work_rate(m, hour())
		var head = agent_by_id(b, reg.queue[0])
		if head != null and head.at_head and rate > 0.0:
			reg.progress += dt * rate / CHECKOUT_TIME
			if reg.progress >= 1.0:
				checkout(b, reg, false)


func checkout(b: Dictionary, reg: Dictionary, manual: bool) -> void:
	var a = agent_by_id(b, reg.queue[0])
	if manual:
		b.combo.count = mini(b.combo.count + 1, int(mods().combo_cap))
		b.combo.timer = COMBO_WINDOW
	var sale := compute_sale(b, a.want)
	apply_sale(b, sale, false, a.x, a.z, reg.id)
	adjust_rating(b, RATING_HAPPY + (RATING_FAST if manual else 0.0))
	if manual:
		emit("combo", {"count": b.combo.count, "x": a.x, "z": a.z})
	if rng.chance(0.05 * mods().spill):
		add_spill(b)
	if mods().loyalty > 0.0 and rng.chance(mods().loyalty):
		b.regulars += 1
	a.state = "leaving"
	a.mood = "happy"
	a.mood_timer = 2.5
	a.bag = "player"
	a.at_head = false
	a.register = -1
	a.path = aisle(local_of(a), DOOR_IN, b.store.size) + [world(DOOR_OUT)]
	a.pi = 0
	reg.queue.pop_front()
	reg.progress = 0.0


func compute_sale(b: Dictionary, pid: String) -> Dictionary:
	var m := mods()
	var h := hour()
	var value: float = PRODUCTS[pid].price * m.price * QUIRKS[b.quirk].get("price", 1.0)
	if h >= 19.0 and m.night > 0.0:
		value *= 1.0 + m.night
	if h < 11.0 and m.morning > 0.0:
		value *= 1.0 + m.morning
	var lucky: bool = m.lucky > 0.0 and rng.chance(m.lucky)
	if lucky:
		value *= 5.0
	var upsell: bool = m.upsell > 0.0 and rng.chance(m.upsell)
	if upsell:
		value *= 1.8
	var charged := value * 0.85 if b.effects.time_sale > 0.0 else value
	var fee := ATM_FEE if b.store.facilities.has("atm") else 0
	var streak: float = 1.0 + m.hot_streak * mini(b.streak.count, 10)
	var golden := 2.0 if m.golden_hour > 0.0 and band(h).rush else 1.0
	return {"revenue": rnd(charged + fee), "damage": value / 10.0 * m.damage * streak * golden,
		"xp": value / 12.0 * m.xp * (1.0 + b.combo.count * m.combo_step), "lucky": lucky, "upsell": upsell, "product": pid}


func apply_sale(b: Dictionary, sale: Dictionary, passive: bool, x: float, z: float, register: int) -> void:
	var r: Dictionary = b.rival
	var dealt := 0.0 if r.defeated else minf(r.hp, sale.damage)
	player.cash += sale.revenue
	player.xp += sale.xp
	r.hp -= dealt
	b.streak.count += 1
	b.streak.timer = STREAK_WINDOW
	var ds: Dictionary = b.day_stats
	ds.revenue += sale.revenue
	ds.rival_damage += dealt
	if passive:
		ds.passive += sale.revenue
	else:
		ds.customers += 1
		run_stats.customers += 1
	run_stats.revenue += sale.revenue
	emit("sale", {"amount": sale.revenue, "lucky": sale.lucky, "upsell": sale.upsell, "product": sale.product, "x": x, "z": z, "passive": passive, "register": register})
	if dealt > 0.0:
		emit("rivalHit", {"damage": dealt, "x": r.x, "z": -9.0})
	check_level_ups()


func update_delivery(b: Dictionary, dt: float) -> void:
	if not b.store.facilities.has("delivery"):
		return
	b.timers.delivery -= dt
	if b.timers.delivery > 0.0:
		return
	var pid: String = rng.pick(b.store.products.keys())
	var sale := compute_sale(b, pid)
	sale.revenue *= 2
	sale.damage *= 2.0
	apply_sale(b, sale, true, DOOR.x, DOOR.y, -1)
	emit("delivery", {"product": pid, "x": DOOR.x, "z": DOOR.y})
	b.timers.delivery = DELIVERY_INTERVAL


func check_level_ups() -> void:
	var gained := false
	while player.xp >= player.xp_next:
		player.xp -= player.xp_next
		player.level += 1
		player.xp_next = xp_for_level(player.level)
		pending.append({"source": "level"})
		gained = true
	if gained:
		emit("levelUp", {"level": player.level})


# ---------- restocking ----------

## Units bought (a partial refill when cash runs short). floor_: cash that must stay in the till.
func restock(b: Dictionary, pid: String, discount: float, floor_: int) -> int:
	var p: Dictionary = b.store.products[pid]
	var missing: int = p.capacity - p.stock
	var each: float = PRODUCTS[pid].cost * mods().restock * discount
	var affordable := floori(maxf(0.0, player.cash - floor_) / each)
	var units := maxi(0, mini(missing, affordable))
	if units > 0:
		var cost := rnd(units * each)
		p.stock += units
		player.cash -= cost
		b.day_stats.restock += cost
		emit("restock", {"product": pid, "units": units, "cost": cost})
	elif missing > 0:
		emit("cantAfford", {"product": pid})
	return units


# ---------- rival ----------

func update_rival(b: Dictionary, dt: float) -> void:
	var r: Dictionary = b.rival
	if r.defeated:
		return
	r.attack_timer -= dt
	r.price_war = maxf(0.0, r.price_war - dt)
	if r.telegraph == "" and r.attack_timer <= 4.0:
		var av := available_attacks(b)
		r.telegraph = rng.pick(av) if not av.is_empty() else "priceWar"
		emit("telegraph", {"attack": r.telegraph})
	if r.attack_timer <= 0.0 and r.telegraph != "":
		launch(b, r.telegraph)
		r.last_attack = r.telegraph
		r.telegraph = ""
		var def: Dictionary = RIVALS[r.id]
		r.attack_timer = maxf(9.0, rng.range_f(def.interval[0], def.interval[1]) * pow(0.93, rival_age(r)) * (0.8 if r.hp / r.max_hp < 0.4 else 1.0))


func available_attacks(b: Dictionary) -> Array:
	var r: Dictionary = b.rival
	var list: Array = RIVALS[r.id].attacks.duplicate()
	if list.size() > 2:
		list.erase(r.last_attack)
	return list.filter(func(at): return attack_ok(b, at))


func attack_ok(b: Dictionary, at: String) -> bool:
	match at:
		"trash":
			return count_threats(b, "trash") < 3
		"flyer", "mascot":
			return not has_threat(b, at, false)
		"takeover":
			return not has_threat(b, "suit", false)
		"blackout":
			return not has_threat(b, "breaker")
		"priceWar":
			return b.rival.price_war <= 0.0
	return true


func threat_clicks(at: String) -> int:
	if at in ["trash", "review"]:
		return 1
	return maxi(1, ATTACKS[at].clicks - int(mods().thick_skin))


func add_threat(b: Dictionary, type: String, at: Vector2, clicks: int, extra := {}) -> Dictionary:
	var t := {"id": take_id(), "type": type, "x": at.x, "z": at.y, "heading": 0.0, "moving": false, "path": [], "pi": 0, "timer": 0.0, "fleeing": false, "clicks": clicks, "max_clicks": clicks}
	t.merge(extra)
	b.threats.append(t)
	return t


func launch(b: Dictionary, at: String) -> void:
	var r: Dictionary = b.rival
	var door := Vector2(r.x, -6.6)
	emit("attack", {"attack": at})
	match at:
		"flyer":
			var t := add_threat(b, "flyer", door, threat_clicks("flyer"), {"phase": "walk"})
			t.path = [Vector2(door.x, FLYER_STAND.y), FLYER_STAND]
		"trash":
			var taken: Array = b.threats.filter(func(t): return t.type == "trash").map(func(t): return t.spot)
			for k in TRASH_SPOTS.size():
				if not taken.has(k):
					add_threat(b, "trash", world(TRASH_SPOTS[k]), 1, {"spot": k})
		"priceWar":
			r.price_war = 20.0
		"mascot":
			var t := add_threat(b, "mascot", door, threat_clicks("mascot"), {"ttl": 40.0, "leg": -1})
			t.timer = 1.0
			t.path = [Vector2(door.x, -5.4), Vector2(MASCOT_TURN, -5.4)]
		"review":
			if b.store.facilities.has("camera") and rng.chance(0.5):
				emit("blocked", {"attack": at})
			else:
				add_threat(b, "review", REVIEW_AT, 1, {"ttl": 7.0 + 3.0 * mods().thick_skin})
		"shoplifter":
			var side := 1.0 if rng.chance(0.5) else -1.0
			var owned: Array = b.store.products.keys()
			var shelf := owned.filter(func(p): return not PRODUCTS[p].get("counter", false))
			var pid: String = rng.pick(shelf if not shelf.is_empty() else owned)
			var spot: Vector2 = SLOTS[PRODUCTS[pid].slot].pick if not shelf.is_empty() else Vector2(3.3, 2.4)
			var t := add_threat(b, "shoplifter", Vector2(26.4 * side, -5.22), threat_clicks("shoplifter"), {"phase": "approach", "product": pid, "spot": spot, "side": side, "inside_t": 0.0})
			t.path = [DOOR]
		"blackout":
			if not has_threat(b, "breaker"):
				add_threat(b, "breaker", world(BREAKER_AT), threat_clicks("blackout"))
		"takeover":
			var starts := [Vector2(24.2, -5.9), Vector2(25.8, -5.4), Vector2(27.4, -4.9)]
			for k in 3:
				var t := add_threat(b, "suit", starts[k], threat_clicks("takeover"), {"speed": 1.0 + 0.1 * k})
				t.path = [DOOR]


func update_threats(b: Dictionary, dt: float) -> void:
	for t0 in b.threats.duplicate():
		var t = threat_by_id(b, t0.id)
		if t == null:
			continue
		if t.fleeing:
			t.path = [Vector2(b.rival.x, -6.6)]
			t.pi = 0
			if follow_once(t, 4.0 * dt):
				remove_threat(b, t.id)
			continue
		match t.type:
			"flyer":
				if t.phase == "walk":
					if follow_once(t, 2.6 * dt):
						t.phase = "post"
						t.moving = false
						t.timer = 1.5
				else:
					t.timer -= dt
					if t.timer <= 0.0:
						poach(b, t, 9.0)
						t.timer = 3.5
			"mascot":
				t.ttl -= dt
				if t.ttl <= 0.0:
					t.fleeing = true
					continue
				if follow_once(t, 1.3 * dt):
					var x: float = MASCOT_TURN if t.leg > 0 else b.rival.x
					t.leg = -t.leg
					t.path = [Vector2(x, -5.4)]
					t.pi = 0
				t.timer -= dt
				if t.timer <= 0.0:
					poach(b, t, 4.5)
					t.timer = 1.2
			"review":
				t.ttl -= dt
				if t.ttl <= 0.0:
					adjust_rating(b, -0.35)
					emit("reviewPosted", {"x": t.x, "z": t.z})
					remove_threat(b, t.id)
			"shoplifter":
				step_shoplifter(b, t, dt)
			"suit":
				if follow_once(t, t.speed * dt):
					var amount := rnd(0.15 * maxf(0.0, player.cash))
					player.cash -= amount
					adjust_rating(b, -0.2)
					emit("takeoverHit", {"amount": amount, "x": t.x, "z": t.z})
					remove_threat(b, t.id)


func step_shoplifter(b: Dictionary, t: Dictionary, dt: float) -> void:
	if t.phase in ["in", "steal"]:
		t.inside_t += dt
		if b.store.facilities.has("camera") and t.inside_t >= 2.5:
			player.cash += 200
			emit("caught", {"x": t.x, "z": t.z, "auto": true})
			remove_threat(b, t.id)
			return
	match t.phase:
		"approach":
			if follow_once(t, 2.1 * dt):
				t.phase = "in"
				t.path = [world(DOOR_IN)] + aisle(DOOR_IN, t.spot, b.store.size)
				t.pi = 0
		"in":
			if follow_once(t, 1.6 * dt):
				t.phase = "steal"
				t.moving = false
				t.timer = 2.2
		"steal":
			t.timer -= dt
			if t.timer <= 0.0:
				var p = b.store.products.get(t.product)
				var units: int = mini(p.stock, 3) if p != null else 0
				if units > 0:
					p.stock -= units
					emit("stolen", {"product": t.product, "units": units, "x": t.x, "z": t.z})
				t.phase = "escape"
				t.path = aisle(local_of(t), DOOR_IN, b.store.size) + [world(DOOR_OUT), Vector2(48.0 * t.side, -5.22)]
				t.pi = 0
		"escape":
			if follow_once(t, 3.2 * dt):
				remove_threat(b, t.id)


## The first walker heading to you within radius who wants something the rival sells goes to the rival instead.
func poach(b: Dictionary, t: Dictionary, radius: float) -> void:
	var sells: Array = RIVALS[b.rival.id].sells
	for a in b.agents:
		if a.state == "walk" and a.target == "player" and a.kind != "fan" and sells.has(a.want) and Vector2(a.x, a.z).distance_to(Vector2(t.x, t.z)) <= radius:
			set_target(b, a, "rival")
			emit("poached", {"x": a.x, "z": a.z})
			return


func add_spill(b: Dictionary) -> void:
	if count_threats(b, "spill") >= MAX_SPILLS:
		return
	var lx := rng.range_f(ZONE_LEFT[b.store.size] + 0.8, 3.0)
	var lz: float = rng.pick(ROWS) + rng.range_f(-0.25, 0.25)
	var t := add_threat(b, "spill", world(Vector2(lx, lz)), 1)
	emit("spill", {"x": t.x, "z": t.z})


## A click, or a staff or cat hit. The last click repels a rival threat (or mops a spill).
func hit_threat(b: Dictionary, t: Dictionary, by := "") -> void:
	if t.fleeing:
		return
	t.clicks -= 1
	emit("threatHit", {"threat": t.type, "x": t.x, "z": t.z, "left": t.clicks, "by": by})
	if t.clicks > 0:
		return
	if t.type == "spill":
		remove_threat(b, t.id)
		player.xp += 2.0
		emit("cleaned", {"threat": t.type, "x": t.x, "z": t.z})
		check_level_ups()
		return
	emit("repelled", {"threat": t.type, "x": t.x, "z": t.z})
	player.xp += 6.0
	if t.type == "shoplifter":
		player.cash += 250
	var r: Dictionary = b.rival
	if not r.defeated:
		var chip := rnd(0.01 * r.max_hp)
		r.hp -= chip
		emit("rivalHit", {"damage": chip, "x": r.x, "z": -9.0, "repel": true})
	if t.type == "review":
		adjust_rating(b, 0.05)
	run_stats.threats_repelled += 1
	if t.type in ["flyer", "mascot", "suit"]:
		t.fleeing = true
	else:
		remove_threat(b, t.id)
	check_level_ups()


func check_defeat(b: Dictionary) -> void:
	var r: Dictionary = b.rival
	if r.defeated or r.hp > 0.0:
		return
	r.defeated = true
	r.hp = 0.0
	r.price_war = 0.0
	r.telegraph = ""
	r.closed_days = 0
	run_stats.rivals_defeated += 1
	pending.append({"source": "reward", "reason": "%s closed for good" % RIVALS[r.id].name})
	emit("rivalDefeated", {"rival": r.id})
	for t in b.threats.duplicate():
		if t.type in ["flyer", "mascot", "suit"]:
			t.fleeing = true
		elif t.type != "spill":
			remove_threat(b, t.id)
	for a in b.agents:
		if a.state == "walk" and a.target == "rival":
			set_target(b, a, "none")


func update_street(b: Dictionary, dt: float) -> void:
	var spills := count_threats(b, "spill")
	if spills > 0:
		adjust_rating(b, -SPILL_DRAIN * spills * dt)
	if b.event != null and b.event.id == "inspector" and not b.event.done and hour() >= 12.0:
		b.event.done = true
		var mess := spills + count_threats(b, "trash")
		if mess == 0:
			adjust_rating(b, 0.2)
			emit("inspection", {"passed": true})
		else:
			var fine := 400 * mess
			player.cash -= fine
			b.day_stats.fines += fine
			adjust_rating(b, -0.3)
			emit("inspection", {"passed": false, "fine": fine})


# ---------- staff ----------

func home_of(b: Dictionary, role: String, slot: int) -> Vector2:
	match role:
		"cashier":
			var regs: Array = b.store.registers.filter(func(r): return r.active)
			return REGISTERS[regs[mini(slot, regs.size() - 1)].id].clerk
		"cat":
			return CAT_HOME
	var homes: Array = STAFF_HOMES[role]
	return homes[slot % homes.size()]


## One body per crew member (and the cat), kept across steps; new ones appear at their home spot.
func sync_staff(b: Dictionary) -> void:
	var want := []
	var count := {}
	for m in b.store.crew:
		want.append([m.role, m.id, count.get(m.role, 0)])
		count[m.role] = count.get(m.role, 0) + 1
	if b.store.facilities.has("cat"):
		want.append(["cat", -1, 0])
	var out := []
	for w in want:
		var s = null
		for o in b.staff:
			if o.crew_id == w[1] and o.role == w[0]:
				s = o
		if s == null:
			var h := world(home_of(b, w[0], w[2]))
			s = {"id": take_id(), "role": w[0], "crew_id": w[1], "slot": w[2], "x": h.x, "z": h.y, "heading": 0.0, "moving": false,
				"path": [], "pi": 0, "task": null, "goal": Vector2.INF, "timer": 0.0, "break_t": 0.0, "work_t": 20.0, "phase": "", "near": false}
		s.slot = w[2]
		out.append(s)
	b.staff = out


func update_staff(b: Dictionary, dt: float) -> void:
	sync_staff(b)
	var claims := {}  # body id -> [role, task] at the start of the phase
	for s in b.staff:
		claims[s.id] = [s.role, s.task]
	var h := hour()
	for s in b.staff.duplicate():
		var m = null
		for c in b.store.crew:
			if c.id == s.crew_id:
				m = c
		if s.role == "cat":
			step_hunter(b, s, dt, RIVAL_THREATS, 4.5, 2.0, 1.1, true, claims)
			continue
		if m == null:
			continue
		if m.trait_id == "slacker":
			if s.break_t > 0.0:
				s.break_t -= dt
				s.moving = false
				if s.break_t <= 0.0:
					s.work_t = rng.range_f(18.0, 30.0)
				continue
			s.work_t -= dt
			if s.work_t <= 0.0:
				s.break_t = rng.range_f(6.0, 10.0)
				emit("staffBreak", {"x": s.x, "z": s.z})
				continue
		var rate := work_rate(m, h)
		var walk := 0.8 + 0.2 * rate
		match s.role:
			"cashier":
				go_to(b, s, world(home_of(b, "cashier", s.slot)), STAFF_WALK * walk * dt)
			"stocker":
				step_stocker(b, s, dt, rate, claims)
			"cleaner":
				step_hunter(b, s, dt, ["spill", "trash"], STAFF_WALK * walk, STAFF_WALK * walk, 1.1 / rate, false, claims)
			"guard":
				step_hunter(b, s, dt, ["flyer", "mascot", "shoplifter", "suit", "breaker"], GUARD_WALK * walk, GUARD_WALK * walk, 0.8 / rate, false, claims)
			"promoter":
				if go_to(b, s, PROMOTER_HOME, STAFF_WALK * walk * dt):
					if not s.near:
						s.near = true
						s.timer = 0.0
					s.timer -= dt
					if s.timer <= 0.0:
						var n := recruit(b, Vector2(s.x, s.z), 9.0, 2)
						if n > 0:
							emit("promote", {"count": n, "x": s.x, "z": s.z})
						s.timer = 6.0 / rate
				else:
					s.near = false


## Walks a body towards goal (world), re-routing when the goal moves; true once there.
func go_to(b: Dictionary, s: Dictionary, goal: Vector2, dist: float) -> bool:
	if Vector2(s.x, s.z).distance_to(goal) < 0.01:
		s.moving = false
		return true
	if s.goal.distance_to(goal) > 0.3 or s.pi >= s.path.size():
		s.goal = goal
		s.path = staff_route(local_of(s), goal - ORIGIN, b.store.size)
		s.pi = 0
	follow_once(s, dist)
	return false


func step_stocker(b: Dictionary, s: Dictionary, dt: float, rate: float, claims: Dictionary) -> void:
	if s.task == null:
		go_to(b, s, world(home_of(b, "stocker", s.slot)), STAFF_WALK * (0.8 + 0.2 * rate) * dt)
		s.timer -= dt
		if s.timer > 0.0:
			return
		s.timer = STOCKER_INTERVAL / rate
		var floor_ := bills_due()
		var best = null
		var best_ratio := STOCKER_THRESHOLD
		for pid in b.store.products:
			var p: Dictionary = b.store.products[pid]
			var ratio: float = float(p.stock) / p.capacity
			if ratio >= best_ratio or claims.keys().any(func(k): return k != s.id and claims[k][0] == "stocker" and claims[k][1] == pid):
				continue
			if floori(maxf(0.0, player.cash - floor_) / (PRODUCTS[pid].cost * mods().restock)) < 1:
				continue
			best = pid
			best_ratio = ratio
		if best != null:
			s.task = best
			s.phase = "walk"
		return
	var slot: Dictionary = SLOTS[PRODUCTS[s.task].slot]
	var stand: Vector2 = slot.pick if slot.has("pick") else Vector2(5.6, slot.pos.y)
	if s.phase == "walk":
		if go_to(b, s, world(stand), STAFF_WALK * (0.8 + 0.2 * rate) * dt):
			s.phase = "work"
			s.timer = STOCKER_WORK / rate
	else:
		s.timer -= dt
		if s.timer <= 0.0:
			if b.store.products.has(s.task):
				restock(b, s.task, 1.0, bills_due())
			s.task = null
			s.phase = ""
			s.timer = STOCKER_INTERVAL / rate


## Cleaners, guards and the cat: keep their target, else take the nearest unclaimed one, else the nearest.
func step_hunter(b: Dictionary, s: Dictionary, dt: float, types: Array, hunt: float, idle: float, interval: float, first_now: bool, claims: Dictionary) -> void:
	var cands: Array = b.threats.filter(func(t): return types.has(t.type) and not t.fleeing)
	if cands.is_empty():
		s.task = null
		s.near = false
		go_to(b, s, world(home_of(b, s.role, s.slot)), idle * dt)
		return
	var me := Vector2(s.x, s.z)
	var tgt = null
	for t in cands:
		if t.id == s.task:
			tgt = t
	if tgt == null:
		var taken := claims.keys().filter(func(k): return k != s.id and claims[k][0] == s.role).map(func(k): return claims[k][1])
		var free := cands.filter(func(t): return not taken.has(t.id))
		var pool: Array = free if not free.is_empty() else cands
		for t in pool:
			if tgt == null or me.distance_to(Vector2(t.x, t.z)) < me.distance_to(Vector2(tgt.x, tgt.z)):
				tgt = t
		s.near = false
	s.task = tgt.id
	var at := Vector2(tgt.x, tgt.z)
	if me.distance_to(at) > REACH:
		s.near = false
		go_to(b, s, at, hunt * dt)
		return
	s.moving = false
	if not s.near:
		s.near = true
		s.timer = 0.0 if first_now else interval
	s.timer -= dt
	if s.timer <= 0.0:
		s.timer = interval
		hit_threat(b, tgt, s.role)
		emit("catSwipe" if s.role == "cat" else "staffHit", {"role": s.role, "x": tgt.x, "z": tgt.z})


## Flyer Blitz and the promoter: walkers nearby who aren't coming yet head to your door; 40% of those who want
## nothing you sell pick something you do.
func recruit(b: Dictionary, center: Vector2, radius: float, limit: int) -> int:
	var n := 0
	for a in b.agents:
		if n >= limit:
			break
		if a.state != "walk" or a.target == "player" or a.kind == "fan" or Vector2(a.x, a.z).distance_to(center) > radius:
			continue
		if not owns(b, a.want):
			if rng.chance(0.4):
				a.want = rng.pick(b.store.products.keys())
			else:
				continue
		set_target(b, a, "player")
		emit("recruit", {"x": a.x, "z": a.z})
		n += 1
	return n


# ---------- picks ----------

func eligible(pool: String, st: Dictionary) -> Array:
	var out := []
	for id in UPGRADES:
		var u: Dictionary = UPGRADES[id]
		if u.pool != pool:
			continue
		var n: int = (st.taken if pool == "expansion" else player.taken).get(id, 0)
		if n >= u.max:
			continue
		if u.has("product") and (st.products.has(u.product) or PRODUCTS[u.product].zone > st.size):
			continue
		out.append(id)
	return out


func card_weight(id: String) -> float:
	var u: Dictionary = UPGRADES[id]
	var progress := mini(4, run_stats.rivals_defeated + branches.size() - 1)
	var w: float = RARITY[u.rarity]
	if u.rarity == "epic":
		w += 1.5 * progress
	elif u.rarity == "legendary":
		w += progress
	if u.has("product"):
		w *= 1.3
	elif u.get("type", "") == "growth":
		w *= 1.6
	return w


func draw_card(ids: Array) -> String:
	return rng.weighted(ids.map(func(id): return [id, card_weight(id)]))


## Three cards without replacement; an expansion offer leads with a product line (or the growth card).
func roll_cards(pool: String, st: Dictionary) -> Array:
	var elig := eligible(pool, st)
	var out := []
	if pool == "expansion":
		var anchor := []
		if st.products.size() < 8:
			anchor = elig.filter(func(id): return UPGRADES[id].has("product"))
		if anchor.is_empty():
			anchor = elig.filter(func(id): return UPGRADES[id].get("type", "") == "growth")
		if not anchor.is_empty():
			var first := draw_card(anchor)
			out.append(first)
			elig.erase(first)
	while out.size() < 3 and not elig.is_empty():
		var c := draw_card(elig)
		out.append(c)
		elig.erase(c)
	return out


func apply_upgrade(id: String) -> void:
	var u: Dictionary = UPGRADES[id]
	var b: Dictionary = branches[active]
	var st: Dictionary = b.store
	var m := mods()
	for k in u.get("add", {}):
		m[k] += u.add[k]
	for k in u.get("mul", {}):
		m[k] *= u.mul[k]
	for k in u.get("store_add", {}):
		st.mods[k] += u.store_add[k]
	if u.has("ability"):
		var ab: Dictionary = player.abilities.get(u.ability, {"level": 0, "cd": 0.0})
		ab.level = mini(3, ab.level + 1)
		ab.cd = 0.0
		player.abilities[u.ability] = ab
	if u.has("product"):
		add_line(st, u.product)
	if u.has("facility"):
		st.facilities.append(u.facility)
	player.cash += u.get("cash", 0)
	match id:
		"floor":
			st.size += 1
		"register2":
			st.registers[1].active = true
		"bigShelves":
			for pid in st.products:
				st.products[pid].capacity = rnd(PRODUCTS[pid].cap * st.mods.capacity)
		"bench":
			st.rating = clampf(st.rating + 0.3, 0.5, 5.0)
		"omotenashi":
			for o in branches:
				o.store.rating = clampf(o.store.rating + 0.5, 0.5, 5.0)
		"r_scholar":
			for o in branches:
				o.store.expansions = maxi(0, o.store.expansions - 1)


func open_pick() -> bool:
	if pending.is_empty():
		return false
	var e: Dictionary = pending[0]
	if not e.has("options"):
		var opts := roll_cards("skill" if e.source == "level" else "reward", branches[active].store)
		if opts.is_empty():
			pending.pop_front()
			player.cash += 3000
			emit("pickPayout", {"amount": 3000})
			return true
		e.options = opts
	choice = {"source": e.source, "options": e.options, "reason": e.get("reason", "")}
	phase = "choice"
	return true


func open_expansion() -> bool:
	var st: Dictionary = branches[active].store
	var elig := eligible("expansion", st)
	if elig.is_empty():
		return false
	if st.offer == null or not st.offer.all(func(id): return elig.has(id)):
		st.offer = roll_cards("expansion", st)
	choice = {"source": "expansion", "options": st.offer, "cost": expansion_cost(st)}
	phase = "choice"
	return true


## Free lots of a profile whose street keeps clear of your branches.
func listing_lots(profile: String) -> Array:
	var out := []
	for i in lots.size():
		if lots[i].use == "free" and profile_of(i) == profile:
			var p := lot_pos(lots[i])
			if branches.all(func(b): return lot_pos(lots[b.lot]).distance_to(p) > BRANCH_GAP):
				out.append(i)
	return out


func roll_listings() -> Array:
	var pool := DISTRICTS.keys().filter(func(d): return not listing_lots(d).is_empty())
	var out := []
	for k in 3:
		if pool.is_empty():
			break
		var d: String = rng.pick(pool)
		pool.erase(d)
		var quirk: String = rng.weighted(QUIRKS.keys().map(func(q): return [q, QUIRKS[q].w]))
		var heat := floori((branches.size() - 1) / 2.0)
		var tier := mini(DISTRICTS[d].tier + heat, 11)
		var rival: String = rng.pick(RIVALS.keys().filter(func(id): return RIVALS[id].tier == mini(tier, 3)))
		var cost := rnd(store_cost() * DISTRICTS[d].cost / 100.0) * 100
		out.append({"district": d, "quirk": quirk, "tier": tier, "rival": rival, "cost": cost, "lot": rng.pick(listing_lots(d))})
	return out


func open_listings() -> bool:
	if branches.size() >= MAX_STORES:
		emit("storeCap")
		return false
	if listing_offer == null:
		listing_offer = roll_listings()
	if listing_offer.is_empty():
		return false
	choice = {"source": "listing", "options": listing_offer}
	phase = "choice"
	return true


func close_choice() -> void:
	choice = null
	phase = "playing"


func pick_choice(id) -> bool:
	if choice == null:
		return false
	match choice.source:
		"level", "reward":
			if not choice.options.has(id):
				return false
			apply_upgrade(id)
			player.taken[id] = player.taken.get(id, 0) + 1
			pending.pop_front()
		"expansion":
			if not choice.options.has(id):
				return false
			var st: Dictionary = branches[active].store
			var cost := expansion_cost(st)
			if player.cash < cost:
				emit("cantAffordExpansion", {"short": cost - player.cash})
				return false
			player.cash -= cost
			apply_upgrade(id)
			st.taken[id] = st.taken.get(id, 0) + 1
			st.expansions += 1
			st.offer = null
		"listing":
			var L: Dictionary = choice.options[id]
			if branches.size() >= MAX_STORES:
				emit("storeCap")
				return false
			if player.cash < L.cost:
				emit("cantAffordStore", {"short": L.cost - player.cash})
				return false
			player.cash -= L.cost
			var b := new_branch(next_branch_id, L, rng, false)
			next_branch_id += 1
			branches.append(b)
			active = branches.size() - 1
			cur = active
			run_stats.stores_opened += 1
			run_stats.peak_stores = maxi(run_stats.peak_stores, branches.size())
			listing_offer = null
			emit("storeOpened", {"name": b.name, "district": b.district, "rival": b.rival.id})
			emit("picked", {"id": "listing", "source": "listing"})
			close_choice()
			return true
	emit("picked", {"id": id, "source": choice.source})
	close_choice()
	return true


func reroll() -> bool:
	if choice == null:
		return false
	var cost := reroll_cost()
	var spare: int = player.cash - (expansion_cost(branches[active].store) if choice.source == "expansion" else 0)
	if spare < cost:
		return false
	player.cash -= cost
	player.rerolls += 1
	match choice.source:
		"expansion":
			var st: Dictionary = branches[active].store
			st.offer = roll_cards("expansion", st)
			choice.options = st.offer
		"listing":
			listing_offer = roll_listings()
			choice.options = listing_offer
		_:
			pending[0].options = roll_cards("skill" if choice.source == "level" else "reward", branches[active].store)
			choice.options = pending[0].options
	emit("reroll")
	return true


# ---------- abilities ----------

func use_ability(id: String) -> bool:
	var ab = player.abilities.get(id)
	if ab == null or ab.level <= 0 or ab.cd > 0.0:
		return false
	var b: Dictionary = branches[active]
	var L: int = ab.level - 1
	var def: Dictionary = ABILITIES[id]
	match id:
		"flyer":
			emit("flyerBlast", {"count": recruit(b, DOOR, def.radius[L], 1 << 30)})
		"timeSale":
			b.effects.time_sale = def.dur[L]
		"counter":
			var r: Dictionary = b.rival
			if not r.defeated:
				var dmg := rnd(r.max_hp * def.pct[L])
				r.hp -= dmg
				r.price_war = 0.0
				r.attack_timer += 10.0
				emit("rivalHit", {"damage": dmg, "x": r.x, "z": -9.0, "big": true})
		"influencer":
			for k in def.fans[L]:
				var x := clampf(DOOR.x + (-1.0 if k % 2 == 0 else 1.0) * rng.range_f(14.0, 26.0), -SPAWN_X, SPAWN_X)
				spawn_agent(b, {"x": x, "north": true, "kind": "fan", "want": rng.pick(b.store.products.keys()), "target": "player"})
			emit("influencer")
		"truck":
			for pid in b.store.products:
				restock(b, pid, def.discount[L], 0)
			emit("truck")
	emit("ability", {"ability": id})
	ab.cd = def.cd[L]
	return true


# ---------- staff hiring ----------

func hire(id: int) -> bool:
	var st: Dictionary = branches[active].store
	var ap = null
	for a in st.applicants:
		if a.id == id:
			ap = a
	if ap == null:
		return false
	if st.crew.filter(func(m): return m.role == ap.role).size() >= role_cap(st, ap.role):
		emit("roleFull", {"role": ap.role})
		return false
	var fee := rnd(ap.wage * mods().wage)
	if player.cash < fee:
		emit("cantAffordHire", {"short": fee - player.cash})
		return false
	player.cash -= fee
	st.applicants = st.applicants.filter(func(a): return a.id != id)
	st.crew.append(ap)
	emit("hired", {"role": ap.role, "name": ap.name, "fee": fee})
	return true


func fire(id: int) -> bool:
	var st: Dictionary = branches[active].store
	for m in st.crew:
		if m.id == id:
			st.crew = st.crew.filter(func(c): return c.id != id)
			emit("fired", {"role": m.role, "name": m.name})
			return true
	return false


# ---------- midnight ----------

func end_day() -> void:
	var rows := []
	for i in branches.size():
		var b: Dictionary = branches[i]
		var ds: Dictionary = b.day_stats
		var rn := rent(b)
		var wg := wages(b)
		rows.append({"branch": b.id, "name": b.name, "stats": ds.duplicate(), "rent": rn, "wages": wg, "rating": b.store.rating,
			"net": ds.revenue - ds.restock - ds.fines - rn - wg, "rival": b.rival.id, "rival_hp": b.rival.hp, "rival_max": b.rival.max_hp, "defeated": b.rival.defeated})
	var cash_before: int = player.cash
	var interest := mini(2000, maxi(0, rnd(player.cash * mods().interest)))
	var bills := 0
	for r in rows:
		bills += r.rent + r.wages
	player.cash += interest - bills
	var foreclosed = null
	if player.cash < 0 and branches.size() > 1:
		var cands := range(branches.size()).filter(func(i): return branches[i].opened < day)
		if cands.is_empty():
			cands = range(branches.size())
		var worst: int = cands[0]
		for i in cands:
			if rows[i].net < rows[worst].net:
				worst = i
		var b: Dictionary = branches[worst]
		var pay := rnd(b.cost * 0.4)
		player.cash += pay
		lots[b.lot].use = "free"
		branches.remove_at(worst)
		if active == worst:
			active = 0
		elif active > worst:
			active -= 1
		run_stats.foreclosed += 1
		foreclosed = {"branch": b.id, "name": b.name, "value": pay}
		emit("foreclosed", foreclosed.duplicate())
	report = {"day": day, "rows": rows, "interest": interest, "bills": bills, "cash_before": cash_before, "cash_after": player.cash, "foreclosed": foreclosed}
	run_stats.days += 1
	if player.cash < 0:
		phase = "gameOver"
		summary = {"kind": "bankrupt", "day": day, "bills": bills, "cash_after": player.cash}
		emit("dayEnd", {"bankrupt": true, "report": report})
		return
	day += 1
	time = 0.0
	for i in branches.size():
		cur = i
		var b: Dictionary = branches[i]
		reset_street(b)
		b.day_stats = zero_stats()
		age_rival(b)
		if day > 1 and b.opened != day and rng.chance(0.4):
			b.event = {"id": rng.weighted(EVENTS.keys().map(func(e): return [e, EVENTS[e].w])), "done": false}
			emit("streetEvent", {"event": b.event.id})
		b.store.applicants = roll_applicants(rng, -1)
	cur = -1
	emit("dayEnd", {"bankrupt": false, "report": report})


func reset_street(b: Dictionary) -> void:
	b.agents = []
	b.threats = []
	b.staff = []
	b.spawn_acc = 0.0
	b.populated = false
	b.effects.time_sale = 0.0
	b.combo = {"count": 0, "timer": 0.0}
	b.streak = {"count": 0, "timer": 0.0}
	for r in b.store.registers:
		r.queue = []
		r.progress = 0.0
	var rv: Dictionary = b.rival
	rv.telegraph = ""
	rv.price_war = 0.0
	rv.attack_timer = RIVALS[rv.id].first * 0.8
	b.event = null


func age_rival(b: Dictionary) -> void:
	var r: Dictionary = b.rival
	if not r.defeated:
		r.days += 1
		return
	r.closed_days += 1
	if r.closed_days < 2:
		return
	b.rival_gen += 1
	var tier := maxi(r.tier + 1, DISTRICTS[b.district].tier + b.rival_gen)
	var pool := RIVALS.keys().filter(func(id): return RIVALS[id].tier == mini(tier, 3))
	if pool.size() > 1:
		pool.erase(r.id)
	b.rival = create_rival(rng.pick(pool), tier)
	emit("rivalArrives", {"rival": b.rival.id, "tier": tier})


func check_milestones() -> void:
	var crew := 0
	for b in branches:
		crew += b.store.crew.size()
	for id in MILESTONES:
		if milestones.has(id):
			continue
		var done := false
		match id:
			"stores2": done = branches.size() >= 2
			"staff5": done = crew >= 5
			"day10": done = day >= 10
			"stores3": done = branches.size() >= 3
			"sales100k": done = run_stats.revenue >= 100000
			"rivals3": done = run_stats.rivals_defeated >= 3
			"staff12": done = crew >= 12
			"day25": done = day >= 25
			"stores5": done = branches.size() >= 5
			"sales1m": done = run_stats.revenue >= 1000000
			"day50": done = day >= 50
		if done:
			milestones[id] = day
			emit("milestone", {"id": id})
			pending.append({"source": "reward", "reason": MILESTONES[id].name})


# ---------- player actions ----------

## One player input, applied to the active store. A rejected action leaves the seed where it was.
func act(a: Dictionary) -> bool:
	rng = Rng.new(rng_seed)
	cur = active
	var changed := false
	var b: Dictionary = branches[active]
	match a.type:
		"start":
			if phase == "intro":
				phase = "playing"
				changed = true
		"restart":
			cur = -1
			start(str(a.seed))
			return true
		"switchStore":
			if phase in ["playing", "intro"] and a.index >= 0 and a.index < branches.size() and a.index != active:
				active = a.index
				emit("switched", {"branch": branches[active].id})
				changed = true
		"pickChoice":
			changed = phase == "choice" and pick_choice(a.id)
		"reroll":
			changed = phase == "choice" and reroll()
		"closeChoice":
			if phase == "choice":
				close_choice()
				changed = true
		_:
			if phase == "playing":
				changed = act_playing(b, a)
	if changed:
		rng_seed = rng.s
	cur = -1
	return changed


func act_playing(b: Dictionary, a: Dictionary) -> bool:
	match a.type:
		"restock":
			return b.store.products.has(a.product) and restock(b, a.product, 1.0, 0) > 0
		"ringUp":
			var reg: Dictionary = b.store.registers[a.register]
			if not reg.active or reg.queue.is_empty():
				return false
			var head = agent_by_id(b, reg.queue[0])
			if head == null or not head.at_head:
				return false
			checkout(b, reg, true)
			return true
		"clickThreat":
			var t = threat_by_id(b, a.id)
			if t == null or t.fleeing:
				return false
			hit_threat(b, t)
			return true
		"useAbility":
			return use_ability(a.id)
		"hire":
			return hire(a.id)
		"fire":
			return fire(a.id)
		"openExpansion":
			return open_expansion()
		"openListings":
			return open_listings()
		"openPick":
			return open_pick()
	return false


# ---------- map ----------

static func lot_pos(lot: Dictionary) -> Vector2:
	return Vector2(lot.x0 + City.LOT_W / 2, lot.front - City.LOT_D / 2)


func city_bounds() -> Rect2:
	return City.get_city().bounds


func branch_on(li: int):
	for b in branches:
		if b.lot == li:
			return b
	return null
