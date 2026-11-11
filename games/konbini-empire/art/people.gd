extends RefCounted
## TODO(people agent): paint art/walk.png's layout in code.


static func walk() -> Image:
	return load("res://art/walk.png").get_image()
