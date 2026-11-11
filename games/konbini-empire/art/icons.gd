extends RefCounted
## TODO(icons agent): paint the products, perks and decor sheets in code.


static func products() -> Image:
	return load("res://art/products.png").get_image()


static func perks() -> Image:
	return load("res://art/perks.png").get_image()


static func decor() -> Image:
	return load("res://art/decor.png").get_image()
