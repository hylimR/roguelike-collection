extends Node
## Sound effects and music, all generated with ElevenLabs. Music follows the hour like an island clock radio: one
## piece for the morning, the afternoon, the evening and the night, replayed after a short breath when it ends.
## The Music and SFX buses let the HUD's sound button mute music, then everything.

const SFX_DB := {
	"door": -16.0, "sale": -14.0, "scan": -10.0, "click": -12.0, "shoo": -8.0, "poof": -8.0, "alert": -6.0,
	"attack": -8.0, "levelup": -4.0, "fanfare": -4.0, "bad": -10.0, "restock": -8.0, "card": -8.0, "closing": -4.0,
	"bankrupt": -4.0, "ability": -6.0,
}
const TRACK_OF := {
	"Morning Rush": "morning", "Late Morning": "morning", "Lunch Rush": "day", "Afternoon": "day",
	"Evening Rush": "evening", "Night": "night", "Last Orders": "night",
}
const MUSIC_DB := -8.0
const MODES := ["Sound on", "Music off", "Muted"]

var players := {}
var last := {}  # sound -> msec it last started, so a busy street doesn't machine-gun the same effect
var music: AudioStreamPlayer
var track := ""
var mode := 0
var fade: Tween


func _ready() -> void:
	for bus in ["Music", "SFX"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")
	for n in SFX_DB:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://audio/sfx/%s.wav" % n)
		p.volume_db = SFX_DB[n]
		p.max_polyphony = 3
		p.bus = "SFX"
		add_child(p)
		players[n] = p
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.volume_db = MUSIC_DB
	music.finished.connect(func(): get_tree().create_timer(3.0).timeout.connect(replay))
	add_child(music)


func play(n: String, pitch := 1.0, gap := 0.06) -> void:
	var now := Time.get_ticks_msec()
	if now - last.get(n, -100000) < gap * 1000.0:
		return
	last[n] = now
	var p: AudioStreamPlayer = players[n]
	p.pitch_scale = pitch
	p.play()


## The piece for this hour; crossfades when the band changes.
func follow(band_name: String) -> void:
	var t: String = TRACK_OF.get(band_name, "morning")
	if t == track:
		return
	track = t
	if fade:
		fade.kill()
	fade = create_tween()
	if music.playing:
		fade.tween_property(music, "volume_db", -40.0, 1.5)
	fade.tween_callback(func():
		music.stream = load("res://audio/music/%s.ogg" % track)
		music.play())
	fade.tween_property(music, "volume_db", MUSIC_DB, 1.0).from(-30.0)


func replay() -> void:
	if not music.playing and track != "":
		music.play()


func stop_music() -> void:
	if fade:
		fade.kill()
	track = ""
	music.stop()


func set_mode(m: int) -> void:
	mode = m
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), mode >= 1)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), mode >= 2)


## Mute everything while the window is in the background (the game pauses then too).
func set_focused(on: bool) -> void:
	AudioServer.set_bus_mute(0, not on)
