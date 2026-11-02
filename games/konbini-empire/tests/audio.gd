extends SceneTree
## Every sound the game asks for exists and loads: the effects named in main.gd and audio.gd, and a music piece
## for each band of the day.
## godot --headless --path games/konbini-empire --script res://tests/audio.gd

const Audio := preload("res://audio.gd")
const Sim := preload("res://sim.gd")


func _init() -> void:
	var fails := []
	var used := {}
	var re := RegEx.create_from_string(r'audio\.play\("(\w+)"')
	for script in ["res://main.gd", "res://audio.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(script)):
			used[m.get_string(1)] = true
	for n in used:
		if not Audio.SFX_DB.has(n):
			fails.append("no volume entry for sound %s" % n)
	for n in Audio.SFX_DB:
		var s = load("res://audio/sfx/%s.wav" % n)
		if not s is AudioStreamWAV or s.get_length() <= 0.05 or s.get_length() > 3.0:
			fails.append("sfx %s missing or odd length" % n)
	for band in Sim.SCHEDULE:
		if not Audio.TRACK_OF.has(band.name):
			fails.append("no music for %s" % band.name)
	for t in Audio.TRACK_OF.values():
		var m = load("res://audio/music/%s.ogg" % t)
		if not m is AudioStreamOggVorbis or m.get_length() < 30.0:
			fails.append("music %s missing or short" % t)
	for f in fails:
		print("FAIL ", f)
	print("AUDIO OK (%d effects, %d used)" % [Audio.SFX_DB.size(), used.size()] if fails.is_empty() else "AUDIO FAIL")
	quit(0 if fails.is_empty() else 1)
