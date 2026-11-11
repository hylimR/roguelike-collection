extends RefCounted
## Every sprite sheet the game draws, painted in code on first use and cached. Each painter keeps its sheet's layout
## (cell size and order, where the art stands in its cell) as its consumers in main.gd and store_view.gd read it.

const People := preload("res://art/people.gd")
const Icons := preload("res://art/icons.gd")
const Fittings := preload("res://art/fittings.gd")

static var images := {}
static var textures := {}


## The sheet as a texture: alpha edges bled (the colour under empty texels is its painted neighbour's, so filtering
## leaves no dark fringe) and mipmapped, as the shop and street sample it.
static func texture(name: String) -> Texture2D:
	if not textures.has(name):
		var img: Image = image(name).duplicate()
		img.fix_alpha_edges()
		img.generate_mipmaps()
		textures[name] = ImageTexture.create_from_image(img)
	return textures[name]


static func image(name: String) -> Image:
	if not images.has(name):
		var img: Image
		match name:
			"walk":
				img = People.walk()
			"products":
				img = Icons.products()
			"perks":
				img = Icons.perks()
			"decor":
				img = Icons.decor()
			"props":
				img = Fittings.props()
			"storefronts":
				img = Fittings.storefronts()
			"konbini_wall":
				img = Fittings.konbini_wall()
			"super_shelves":
				img = Fittings.super_shelves()
			_:
				push_error("no sheet named " + name)
				return null
		img.clear_mipmaps()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		images[name] = img
	return images[name]
