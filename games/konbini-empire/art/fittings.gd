extends RefCounted
## TODO(fittings agent): paint the props and storefronts sheets and the two shops' back walls in code.


static func props() -> Image:
	return load("res://art/props.png").get_image()


static func storefronts() -> Image:
	return load("res://art/storefronts.png").get_image()


## Your shop's back wall seen from the floor: stripes, fridges, the staff door.
static func konbini_wall() -> Image:
	return load("res://art/bg_konbini.png").get_image().get_region(Rect2i(208, 44, 316, 201))


## A supermarket's shelves seen through its glass front.
static func super_shelves() -> Image:
	return load("res://art/bg_super.png").get_image().get_region(Rect2i(80, 126, 560, 119))
