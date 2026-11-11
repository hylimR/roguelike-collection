extends RefCounted
## The street's traffic, built in code at real size: kei car, taxi, kei truck and the courier's scooter (store_view's
## kv 0-3), one ArrayMesh per kind (and kei paint) shared by every vehicle of it. Metres: x forward (the nose at +x),
## y up from the road, z to the vehicle's right. Faces carry their colour, not their tone: SHADER gives each the
## house's tone for the way it faces in the world, so a car turning to its heading keeps the sun where the buildings
## have it. Lamps light up after dark.

const KEI := 0
const TAXI := 1
const TRUCK := 2
const SCOOTER := 3
## Each kind's length and width.
const SIZE: Array[Vector2] = [Vector2(3.4, 1.48), Vector2(4.7, 1.7), Vector2(3.4, 1.48), Vector2(1.8, 0.7)]
## Each kind's front axle (x) and wheel radius.
const WHEEL: Array[Vector2] = [Vector2(1.17, 0.27), Vector2(1.4, 0.31), Vector2(1.02, 0.26), Vector2(0.62, 0.23)]
## The kei car's paints: sky blue, cream and blossom pink.
const PAINTS: Array[Color] = [Color("84c6f2"), Color("f1e9d4"), Color("f2aab7")]
const GLASS := Color("3a4d6c")
const TYRE := Color("2a2a2e")
const HUB := Color("c5c9cc")
const UNDER := Color("2c2d33")
const HEAD := Color("f7f1dc")
const TAIL := Color("e5352b")
const AMBER := Color("f0a030")
const KEI_PLATE := Color("f2cd3c")
const INK := Color("3a3424")
## Faces toned by world normal (as store_view's boxes and art/shapes.gd bake theirs: tops full, walls turned to the sun
## 0.9, walls away 0.75, undersides 0.7) and lit like a mat() material, its vertex colour taken as sRGB; after dark a
## vehicle's `lift` (how far it stands into a street lamp's pool) draws its light toward the lamps'. A face whose uv.x
## is 1 is a lamp: after dark (with `lamps` on) it shows its own colour, untoned and unlit.
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 light : source_color = vec4(1.0);
uniform vec4 lamp : source_color = vec4(1.0);
uniform float night = 0.0;
uniform float lamps = 1.0;
instance uniform float lift = 0.0;
varying float glow;

void vertex() {
	vec3 n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float side = n.z - n.x > 0.0 ? 0.9 : 0.75;
	float tone = n.y > 0.0 ? mix(side, 1.0, n.y) : mix(side, 0.7, -n.y);
	glow = UV.x * night * lamps;
	COLOR.rgb *= mix(tone, 1.0, glow);
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(mix(light.rgb, lamp.rgb, lift * night), vec3(1.0), glow);
}
"""

static var meshes := {}
static var shadows := {}
static var mats := {}
static var shader: Shader
static var light := Color.WHITE
static var lamp := Color.WHITE
static var night := 0.0


## The shared mesh for kind kv (a kei car in PAINTS[paint]).
static func mesh(kv: int, paint := 0) -> ArrayMesh:
	var key := kv * 8 + (paint if kv == KEI else 0)
	if not meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		match kv:
			KEI:
				kei(st, PAINTS[paint])
			TAXI:
				taxi(st)
			TRUCK:
				truck(st)
			_:
				scooter(st)
		st.index()
		st.set_material(material(true))
		meshes[key] = st.commit()
	return meshes[key]


## The vehicles' material, its lamps lit after dark or left off (a parked car).
static func material(lamps: bool) -> ShaderMaterial:
	if not mats.has(lamps):
		if not shader:
			shader = Shader.new()
			shader.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("lamps", 1.0 if lamps else 0.0)
		m.set_shader_parameter("light", light)
		m.set_shader_parameter("lamp", lamp)
		m.set_shader_parameter("night", night)
		mats[lamps] = m
	return mats[lamps]


## Follows the hour: the light the vehicles stand in, how far night has fallen and the street lamps' light (store_view's
## light, night and LAMP).
static func relight(light_: Color, night_: float, lamp_: Color) -> void:
	light = light_
	night = night_
	lamp = lamp_
	for m in mats.values():
		m.set_shader_parameter("light", light)
		m.set_shader_parameter("lamp", lamp)
		m.set_shader_parameter("night", night)


## A soft shadow under kind kv, 0.25 m round its footprint: a radial gradient (store_view's soft_mat) stretched through
## nine slices, so it fades straight off the sides and round at the corners.
static func shadow(kv: int) -> ArrayMesh:
	if not shadows.has(kv):
		var h := SIZE[kv] / 2 + Vector2(0.25, 0.25)
		var f := minf(0.55, h.y * 0.8)
		var xs := [-h.x, -h.x + f, h.x - f, h.x]
		var zs := [-h.y, -h.y + f, h.y - f, h.y]
		var uv := [0.0, 0.5, 0.5, 1.0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 3:
			for j in 3:
				for c in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
					st.set_uv(Vector2(uv[i + c[0]], uv[j + c[1]]))
					st.add_vertex(Vector3(xs[i + c[0]], 0.0, zs[j + c[1]]))
		shadows[kv] = st.commit()
	return shadows[kv]


# ---------- the vehicles ----------

## A kei hatchback: a tall cabin over a short bonnet, yellow plates, upright tail lamps up its back corners.
static func kei(st: SurfaceTool, paint: Color) -> void:
	var w := WHEEL[KEI]
	var body := PackedVector2Array([Vector2(-1.66, 0.2)])
	body.append_array(arch(Vector2(-w.x, w.y), 0.335, 0.2))
	body.append_array(arch(Vector2(w.x, w.y), 0.335, 0.2))
	body.append_array([Vector2(1.66, 0.2), Vector2(1.7, 0.26), Vector2(1.7, 0.74), Vector2(1.63, 0.81), Vector2(1.04, 0.94), Vector2(-1.66, 0.96), Vector2(-1.7, 0.9), Vector2(-1.7, 0.26)])
	prism(st, body, 0.74, paint)
	var cab := PackedVector2Array([Vector2(1.04, 0.94), Vector2(0.42, 1.55), Vector2(0.3, 1.6), Vector2(-1.52, 1.6), Vector2(-1.6, 1.56), Vector2(-1.66, 0.96)])
	var lean := 0.125
	prism(st, cab, 0.7, paint, lean, 0.94)
	var mid := Vector3(-0.3, 1.2, 0.0)
	edge_glass(st, cab[0], cab[1], 0.7, lean, 0.94, 0.05, Vector2(0.05, 0.93), mid)
	edge_glass(st, cab[4], cab[5], 0.7, lean, 0.94, 0.07, Vector2(0.08, 0.9), mid)
	side_glass(st, cab, 0.7, lean, 0.94, 0.065, 0.99, [Vector2(-0.26, 1.2), Vector2(-1.18, -0.36), Vector2(-1.7, -1.27)])
	axles(st, [w.x, -w.x], w.y, 0.17, 0.7, 0.335, 0.2, -1.5)
	for seam in [Vector2(0.98, 0.56), Vector2(-0.31, 0.26)]:
		on_side(st, rect(seam.x - 0.011, seam.y, seam.x + 0.011, 0.93), 0.74, paint.darkened(0.3))
	for x in [0.5, -0.56]:
		on_side(st, rect(x, 0.79, x + 0.11, 0.82), 0.74, paint.darkened(0.4))
	on_side(st, rect(1.38, 0.68, 1.48, 0.72), 0.74, AMBER)
	for s in [-1.0, 1.0]:
		box(st, Vector3(0.86, 0.98, s * 0.7), Vector3(0.98, 1.08, s * 0.84), UNDER)
		box(st, Vector3(1.69, 0.56, s * 0.36), Vector3(1.715, 0.72, s * 0.66), HEAD, 1.0)
		box(st, Vector3(-1.715, 0.56, s * 0.52), Vector3(-1.69, 0.92, s * 0.7), TAIL, 1.0)
	box(st, Vector3(1.7, 0.58, -0.3), Vector3(1.712, 0.68, 0.3), Color("3a4048"))
	for e in [1.0, -1.0]:
		box(st, Vector3(1.66, 0.22, -0.72) * Vector3(e, 1, 1), Vector3(1.73, 0.5, 0.72) * Vector3(e, 1, 1), paint.darkened(0.08))
		box(st, Vector3(1.73, 0.25, -0.38) * Vector3(e, 1, 1), Vector3(1.736, 0.29, 0.38) * Vector3(e, 1, 1), UNDER)
	plate(st, Vector3(1.735, 0.3, 0.0), 1.0, KEI_PLATE, INK)
	plate(st, Vector3(-1.705, 0.6, 0.0), -1.0, KEI_PLATE, INK)


## A Tokyo taxi: a deep-green three-box sedan with a gold line down its flanks, chrome grille and bumpers, mirrors on
## its front wings, the lamp on its roof and the red vacancy sign behind the windscreen lit after dark.
static func taxi(st: SurfaceTool) -> void:
	var paint := Color("2c7349")
	var chrome := Color("c3c7cb")
	var w := WHEEL[TAXI]
	var body := PackedVector2Array([Vector2(-2.32, 0.22)])
	body.append_array(arch(Vector2(-w.x, w.y), 0.37, 0.22))
	body.append_array(arch(Vector2(w.x, w.y), 0.37, 0.22))
	body.append_array([Vector2(2.32, 0.22), Vector2(2.36, 0.28), Vector2(2.36, 0.66), Vector2(2.3, 0.78), Vector2(1.12, 0.86), Vector2(-1.48, 0.9), Vector2(-2.28, 0.88), Vector2(-2.36, 0.8), Vector2(-2.36, 0.28)])
	prism(st, body, 0.85, paint)
	var cab := PackedVector2Array([Vector2(1.12, 0.86), Vector2(0.34, 1.44), Vector2(0.2, 1.5), Vector2(-0.9, 1.5), Vector2(-1.04, 1.45), Vector2(-1.5, 0.9)])
	var lean := 0.15
	prism(st, cab, 0.8, paint, lean, 0.86)
	var mid := Vector3(-0.2, 1.15, 0.0)
	edge_glass(st, cab[0], cab[1], 0.8, lean, 0.86, 0.05, Vector2(0.05, 0.93), mid)
	edge_glass(st, cab[4], cab[5], 0.8, lean, 0.86, 0.07, Vector2(0.08, 0.9), mid)
	side_glass(st, cab, 0.8, lean, 0.86, 0.065, 0.92, [Vector2(-0.12, 1.3), Vector2(-0.98, -0.22)])
	axles(st, [w.x, -w.x], w.y, 0.19, 0.81, 0.37, 0.22, -2.1)
	on_side(st, rect(-2.34, 0.66, 2.34, 0.7), 0.85, Color("e8c040"))
	for x in [1.0, -0.17, -1.0]:
		on_side(st, rect(x - 0.011, 0.26, x + 0.011, 0.88), 0.85, paint.darkened(0.35))
	for x in [0.62, -0.5]:
		on_side(st, rect(x, 0.76, x + 0.12, 0.79), 0.85, chrome)
	for s in [-1.0, 1.0]:
		box(st, Vector3(1.84, 0.8, s * 0.64), Vector3(1.86, 0.94, s * 0.66), UNDER)
		box(st, Vector3(1.81, 0.92, s * 0.62), Vector3(1.89, 1.0, s * 0.75), UNDER)
		box(st, Vector3(2.35, 0.48, s * 0.44), Vector3(2.375, 0.64, s * 0.78), HEAD, 1.0)
		box(st, Vector3(2.4, 0.3, s * 0.62), Vector3(2.41, 0.38, s * 0.8), AMBER)
		box(st, Vector3(-2.375, 0.56, s * 0.46), Vector3(-2.35, 0.76, s * 0.82), TAIL, 1.0)
	box(st, Vector3(2.355, 0.48, -0.4), Vector3(2.37, 0.64, 0.4), chrome)
	for y in [0.52, 0.57]:
		box(st, Vector3(2.37, y, -0.38), Vector3(2.375, y + 0.022, 0.38), UNDER)
	for e in [1.0, -1.0]:
		box(st, Vector3(2.32, 0.24, -0.84) * Vector3(e, 1, 1), Vector3(2.4, 0.42, 0.84) * Vector3(e, 1, 1), chrome)
	plate(st, Vector3(2.405, 0.255, 0.0), 1.0, Color("2f7a4a"), Color("eef2ea"))
	plate(st, Vector3(-2.365, 0.48, 0.0), -1.0, Color("2f7a4a"), Color("eef2ea"))
	hull(st, rect3(-0.36, 0.0, 0.16, 1.5), rect3(-0.32, -0.04, 0.11, 1.65), Color("f6cf3a"), 1.0)
	box(st, Vector3(-0.38, 1.49, -0.18), Vector3(0.02, 1.52, 0.18), UNDER)
	box(st, Vector3(0.94, 0.88, -0.64), Vector3(1.01, 0.98, -0.4), Color("e33a2c"), 1.0)


## A kei truck: a white cab over its front wheels, the flatbed's drop sides ribbed, a guard frame behind the cab, and
## taped cardboard boxes stacked on the bed.
static func truck(st: SurfaceTool) -> void:
	var paint := Color("f4f1ea")
	var w := WHEEL[TRUCK]
	var body := PackedVector2Array([Vector2(0.42, 0.3)])
	body.append_array(arch(Vector2(w.x, w.y), 0.33, 0.3))
	body.append_array([Vector2(1.66, 0.3), Vector2(1.7, 0.36), Vector2(1.7, 1.04), Vector2(0.42, 1.04)])
	prism(st, body, 0.74, paint)
	var cab := PackedVector2Array([Vector2(1.7, 1.04), Vector2(1.48, 1.72), Vector2(1.38, 1.8), Vector2(0.48, 1.8), Vector2(0.42, 1.74), Vector2(0.42, 1.04)])
	var lean := 0.05
	prism(st, cab, 0.73, paint, lean, 1.04)
	var mid := Vector3(1.0, 1.4, 0.0)
	edge_glass(st, cab[0], cab[1], 0.73, lean, 1.04, 0.05, Vector2(0.06, 0.92), mid)
	edge_glass(st, cab[4], cab[5], 0.73, lean, 1.04, 0.2, Vector2(0.15, 0.72), mid)
	side_glass(st, cab, 0.73, lean, 1.04, 0.07, 1.1, [Vector2(0.62, 1.8)])
	on_side(st, rect(0.5, 0.34, 0.522, 1.04), 0.74, paint.darkened(0.25))
	on_side(st, rect(0.5, 1.04, 0.522, 1.74), 0.73, paint.darkened(0.25), lean, 1.04)
	on_side(st, rect(0.6, 0.96, 0.72, 0.99), 0.74, paint.darkened(0.45))
	axles(st, [w.x], w.y, 0.16, 0.69, 0.33, 0.3, 0.0)
	for s in [-1.0, 1.0]:
		wheel(st, Vector3(-0.86, w.y, s * 0.61), w.y, 0.16)
		box(st, Vector3(1.52, 1.18, s * 0.73), Vector3(1.6, 1.36, s * 0.82), UNDER)
		box(st, Vector3(1.7, 0.58, s * 0.44), Vector3(1.722, 0.74, s * 0.66), HEAD, 1.0)
		box(st, Vector3(1.7, 0.51, s * 0.5), Vector3(1.716, 0.56, s * 0.66), AMBER)
		box(st, Vector3(-1.765, 0.46, s * 0.5), Vector3(-1.74, 0.58, s * 0.7), TAIL, 1.0)
	box(st, Vector3(1.7, 0.62, -0.36), Vector3(1.712, 0.7, 0.36), Color("3a4048"))
	box(st, Vector3(1.68, 0.3, -0.73), Vector3(1.75, 0.5, 0.73), Color("3d4654"))
	plate(st, Vector3(1.755, 0.32, 0.0), 1.0, KEI_PLATE, INK)
	box(st, Vector3(-1.55, 0.3, -0.5), Vector3(0.42, 0.6, 0.5), UNDER)
	box(st, Vector3(-1.76, 0.36, -0.7), Vector3(-1.66, 0.46, 0.7), Color("3d4654"))
	plate(st, Vector3(-1.765, 0.42, 0.0), -1.0, KEI_PLATE, INK)
	var gate := Color("ebe8e1")
	box(st, Vector3(-1.7, 0.6, -0.74), Vector3(0.4, 0.7, 0.74), Color("d9d6cf"))
	for s in [-1.0, 1.0]:
		box(st, Vector3(-1.7, 0.7, s * 0.7), Vector3(0.4, 1.0, s * 0.74), gate)
		for y in [0.79, 0.89]:
			box(st, Vector3(-1.68, y, s * 0.74), Vector3(0.38, y + 0.018, s * 0.748), gate.darkened(0.16))
		box(st, Vector3(-0.67, 0.7, s * 0.74), Vector3(-0.63, 1.0, s * 0.75), gate.darkened(0.1))
	box(st, Vector3(-1.7, 0.7, -0.74), Vector3(-1.66, 1.0, 0.74), gate)
	box(st, Vector3(0.36, 0.7, -0.74), Vector3(0.4, 1.0, 0.74), gate)
	for s in [-1.0, 1.0]:
		box(st, Vector3(0.3, 1.0, s * 0.66), Vector3(0.36, 1.84, s * 0.72), gate)
	box(st, Vector3(0.3, 1.78, -0.72), Vector3(0.36, 1.84, 0.72), gate)
	for z in [-0.33, 0.0, 0.33]:
		box(st, Vector3(0.32, 1.0, z - 0.014), Vector3(0.34, 1.78, z + 0.014), gate)
	for b in [[Vector3(0.0, 0.91, -0.33), Vector3(0.56, 0.42, 0.56), 0.0], [Vector3(0.02, 0.91, 0.31), Vector3(0.52, 0.42, 0.52), 0.06],
			[Vector3(-0.62, 0.89, -0.28), Vector3(0.56, 0.38, 0.54), -0.05], [Vector3(-0.02, 1.3, -0.06), Vector3(0.48, 0.36, 0.5), 0.1]]:
		var xf := Transform3D(Basis(Vector3.UP, b[2]), b[0])
		turned(st, xf.scaled_local(b[1]), Color("d0924f"))
		turned(st, xf * Transform3D(Basis.from_scale(Vector3(b[1].x + 0.004, 0.006, 0.12)), Vector3(0, b[1].y / 2, 0)), Color("e8c48e"))


## A delivery scooter in cream and navy with its red top box, the courier in a red jacket and white helmet aboard.
static func scooter(st: SurfaceTool) -> void:
	var cream := Color("f2e8cf")
	var navy := Color("2f4470")
	var red := Color("e0332b")
	var w := WHEEL[SCOOTER]
	for x in [w.x, -0.6]:
		wheel(st, Vector3(x, w.y, 0.0), w.y, 0.09)
	for s in [-1.0, 1.0]:
		beam(st, Vector3(w.x, w.y, s * 0.06), Vector3(0.5, 0.92, s * 0.06), Vector2(0.035, 0.035), Color("50555e"))
	box(st, Vector3(0.44, 0.46, -0.065), Vector3(0.84, 0.52, 0.065), navy)
	box(st, Vector3(-0.84, 0.46, -0.065), Vector3(-0.44, 0.52, 0.065), cream)
	hull(st, rect3(0.3, 0.44, 0.21, 0.36), rect3(0.36, 0.48, 0.2, 0.92), cream)
	hull(st, rect3(0.31, 0.46, 0.215, 0.32), rect3(0.33, 0.47, 0.205, 0.5), navy)
	box(st, Vector3(-0.12, 0.3, -0.14), Vector3(0.34, 0.37, 0.14), Color("3a3d44"))
	box(st, Vector3(-0.12, 0.18, -0.11), Vector3(0.2, 0.36, 0.11), Color("4a4d55"))
	box(st, Vector3(-0.62, 0.2, 0.12), Vector3(0.1, 0.27, 0.19), Color("a9adb2"))
	hull(st, rect3(-0.72, 0.0, 0.16, 0.3), rect3(-0.66, -0.06, 0.15, 0.72), cream)
	box(st, Vector3(-0.6, 0.36, -0.165), Vector3(-0.1, 0.52, 0.165), navy)
	box(st, Vector3(-0.58, 0.72, -0.13), Vector3(0.02, 0.8, 0.13), Color("2a2a2e"))
	box(st, Vector3(-0.92, 0.8, -0.14), Vector3(-0.44, 0.83, 0.14), Color("4a4d55"))
	box(st, Vector3(-0.95, 0.83, -0.24), Vector3(-0.41, 1.29, 0.24), red)
	box(st, Vector3(-0.955, 1.17, -0.245), Vector3(-0.405, 1.185, 0.245), red.darkened(0.3))
	box(st, Vector3(-0.9, 1.02, -0.245), Vector3(-0.46, 1.05, 0.245), cream)
	box(st, Vector3(-0.91, 0.52, -0.04), Vector3(-0.89, 0.8, 0.04), UNDER)
	box(st, Vector3(-0.935, 0.7, -0.05), Vector3(-0.91, 0.77, 0.05), TAIL, 1.0)
	box(st, Vector3(-0.93, 0.56, -0.09), Vector3(-0.91, 0.66, 0.09), Color("f4f4f0"))
	box(st, Vector3(0.38, 0.9, -0.11), Vector3(0.56, 1.02, 0.11), navy)
	box(st, Vector3(0.555, 0.92, -0.06), Vector3(0.575, 1.0, 0.06), HEAD, 1.0)
	box(st, Vector3(0.4, 0.99, -0.32), Vector3(0.44, 1.02, 0.32), UNDER)
	for s in [-1.0, 1.0]:
		beam(st, Vector3(0.42, 1.0, s * 0.22), Vector3(0.39, 1.22, s * 0.27), Vector2(0.015, 0.015), UNDER)
		box(st, Vector3(0.37, 1.2, s * 0.24), Vector3(0.41, 1.27, s * 0.32), UNDER)
	var jeans := Color("34507a")
	var jacket := Color("dd2f27")
	for s in [-1.0, 1.0]:
		beam(st, Vector3(-0.24, 0.86, s * 0.11), Vector3(0.16, 0.92, s * 0.14), Vector2(0.15, 0.15), jeans)
		beam(st, Vector3(0.16, 0.92, s * 0.14), Vector3(0.14, 0.44, s * 0.13), Vector2(0.12, 0.12), jeans)
		box(st, Vector3(0.08, 0.37, s * 0.07), Vector3(0.3, 0.46, s * 0.19), Color("5a3a28"))
		beam(st, Vector3(-0.12, 1.34, s * 0.19), Vector3(0.16, 1.1, s * 0.25), Vector2(0.11, 0.11), jacket)
		beam(st, Vector3(0.16, 1.1, s * 0.25), Vector3(0.4, 1.02, s * 0.29), Vector2(0.1, 0.1), jacket)
		box(st, Vector3(0.39, 0.98, s * 0.25), Vector3(0.46, 1.05, s * 0.32), UNDER)
	beam(st, Vector3(-0.27, 0.84, 0.0), Vector3(-0.12, 1.42, 0.0), Vector2(0.4, 0.26), jacket)
	var helmet := Vector3(-0.08, 0.0, 0.0)
	drum(st, helmet, 0.15, 0.15, 1.42, 1.6, Color("f2f1ec"))
	drum(st, helmet, 0.15, 0.08, 1.6, 1.7, Color("f2f1ec"))
	for k: int in [-1, 0, 1]:
		var a0 := (k - 0.5) * TAU / 8
		var a1 := (k + 0.5) * TAU / 8
		var q := [Vector3(cos(a0), 1.47, sin(a0)), Vector3(cos(a1), 1.47, sin(a1)), Vector3(cos(a1), 1.57, sin(a1)), Vector3(cos(a0), 1.57, sin(a0))]
		face(st, q.map(func(p: Vector3): return helmet + Vector3(p.x * 0.155, p.y, p.z * 0.155)), Color("232c3c"), helmet + Vector3(0, 1.52, 0))


# ---------- parts ----------

## A flat convex polygon facing away from `inside`; glow 1 marks a lamp.
static func face(st: SurfaceTool, pts: Array, col: Color, inside: Vector3, glow := 0.0) -> void:
	var n := Vector3.ZERO
	for i in pts.size():
		n += (pts[i] as Vector3).cross(pts[(i + 1) % pts.size()])
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	if n.dot(pts[0] - inside) < 0.0:
		n = -n
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(Vector2(glow, 0.0))
	for i in range(1, pts.size() - 1):
		st.add_vertex(pts[0])
		st.add_vertex(pts[i])
		st.add_vertex(pts[i + 1])


## A box between corners a and b.
static func box(st: SurfaceTool, a: Vector3, b: Vector3, col: Color, glow := 0.0) -> void:
	turned(st, Transform3D(Basis.from_scale((b - a).abs()), (a + b) / 2), col, glow)


## A unit box (corners at ±0.5) under xf.
static func turned(st: SurfaceTool, xf: Transform3D, col: Color, glow := 0.0) -> void:
	var c := []
	for i in 8:
		c.append(xf * Vector3((i & 1) - 0.5, ((i >> 1) & 1) - 0.5, ((i >> 2) & 1) - 0.5))
	for f in [[2, 3, 7, 6], [4, 5, 7, 6], [0, 1, 3, 2], [1, 3, 7, 5], [0, 2, 6, 4], [0, 1, 5, 4]]:
		face(st, f.map(func(i: int): return c[i]), col, xf.origin, glow)


## A box from rectangle lo up to rectangle hi (four corners each, in the same order): a cabin, a lamp, a fairing.
static func hull(st: SurfaceTool, lo: Array, hi: Array, col: Color, glow := 0.0) -> void:
	var inside := Vector3.ZERO
	for p in lo + hi:
		inside += p / 8.0
	face(st, hi, col, inside, glow)
	face(st, lo, col, inside, glow)
	for i in 4:
		face(st, [lo[i], lo[(i + 1) % 4], hi[(i + 1) % 4], hi[i]], col, inside, glow)


## The corners of a level rectangle from x0 to x1, hz either side of the centre line, at height y.
static func rect3(x0: float, x1: float, hz: float, y: float) -> Array:
	return [Vector3(x0, y, -hz), Vector3(x1, y, -hz), Vector3(x1, y, hz), Vector3(x0, y, hz)]


## A rectangle in a profile (x, y).
static func rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## A box from a to b, `size` across (z, then the other way round it): a fork, a mirror's stalk, a limb.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, size: Vector2, col: Color) -> void:
	var d := (b - a).normalized()
	var z := (Vector3.BACK - d * d.z).normalized()
	turned(st, Transform3D(Basis(d * a.distance_to(b), z.cross(d) * size.y, z * size.x), (a + b) / 2), col)


## A drum about the vertical through c, radius r0 at y0 to r1 at y1, eight faces with one facing forward, capped.
static func drum(st: SurfaceTool, c: Vector3, r0: float, r1: float, y0: float, y1: float, col: Color) -> void:
	var inside := c + Vector3(0, (y0 + y1) / 2, 0)
	var top := []
	var foot := []
	for i in 8:
		var a0 := (i - 0.5) * TAU / 8
		var a1 := (i + 0.5) * TAU / 8
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		face(st, [c + d0 * r0 + Vector3(0, y0, 0), c + d1 * r0 + Vector3(0, y0, 0), c + d1 * r1 + Vector3(0, y1, 0), c + d0 * r1 + Vector3(0, y1, 0)], col, inside)
		top.append(c + d0 * r1 + Vector3(0, y1, 0))
		foot.append(c + d0 * r0 + Vector3(0, y0, 0))
	face(st, top, col, inside)
	face(st, foot, col, inside)


## A wheel at c, its axle across: a tyre of ten faces w wide, and a hubcap on its outer face (both, on the centre line).
static func wheel(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	var rim := []
	for i in 10:
		var a := TAU * (i + 0.5) / 10
		rim.append(Vector2(cos(a), sin(a)))
	for i in 10:
		var p: Vector2 = rim[i] * r
		var q: Vector2 = rim[(i + 1) % 10] * r
		face(st, [c + Vector3(p.x, p.y, -w / 2), c + Vector3(q.x, q.y, -w / 2), c + Vector3(q.x, q.y, w / 2), c + Vector3(p.x, p.y, w / 2)], TYRE, c)
	for s in [-1.0, 1.0]:
		face(st, rim.map(func(v: Vector2): return c + Vector3(v.x * r, v.y * r, s * w / 2)), TYRE, c)
		if signf(c.z) == s or c.z == 0.0:
			face(st, rim.map(func(v: Vector2): return c + Vector3(v.x * r * 0.55, v.y * r * 0.55, s * (w / 2 + 0.004))), HUB, c)


## A wheel each side at each axle x (its outer face hw out), with a dark well in the arch (radius ra over the foot yb)
## and, for x_rear behind the middle, the floor's dark underside from there to the front axle.
static func axles(st: SurfaceTool, xs: Array, r: float, w: float, hw: float, ra: float, yb: float, x_rear: float) -> void:
	for x in xs:
		for s in [-1.0, 1.0]:
			wheel(st, Vector3(x, r, s * (hw - w / 2)), r, w)
		on_side(st, arch(Vector2(x, r), ra, yb), hw - w - 0.03, UNDER, 0.0, 0.0, 0.0, 0.0)
	if x_rear < 0.0:
		box(st, Vector3(x_rear, yb - 0.08, -(hw - 0.1)), Vector3(xs[0], yb, hw - 0.1), UNDER)


## A wheel arch cut up into a profile's foot at yb, round from behind the wheel at c to in front of it.
static func arch(c: Vector2, r: float, yb: float) -> PackedVector2Array:
	var a0 := asin(clampf((yb - c.y) / r, -1.0, 1.0))
	var out := PackedVector2Array()
	for k in 9:
		var a := lerpf(PI - a0, a0, k / 8.0)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## Profile prof (x, y) extruded across from -hw to hw, its sides leaning in by `lean` a metre above y0 (a cabin's
## tumblehome). Its sides are triangulated, so a body's profile can have its wheel arches cut out of it.
static func prism(st: SurfaceTool, prof: PackedVector2Array, hw: float, col: Color, lean := 0.0, y0 := 0.0) -> void:
	var area := 0.0
	for i in prof.size():
		area += prof[i].cross(prof[(i + 1) % prof.size()])
	for i in prof.size():
		var a := prof[i]
		var b := prof[(i + 1) % prof.size()]
		var into := Vector2(a.y - b.y, b.x - a.x).normalized() * signf(area) * 0.05
		var za := hw - lean * (a.y - y0)
		var zb := hw - lean * (b.y - y0)
		face(st, [Vector3(a.x, a.y, -za), Vector3(b.x, b.y, -zb), Vector3(b.x, b.y, zb), Vector3(a.x, a.y, za)], col, Vector3((a.x + b.x) / 2 + into.x, (a.y + b.y) / 2 + into.y, 0.0))
	on_side(st, prof, hw, col, lean, y0, 0.0, 0.0)


## A polygon (x, y) laid on both sides of a prism of half width hw (leaning in by `lean` above y0), `lift` proud of it.
static func on_side(st: SurfaceTool, poly: PackedVector2Array, hw: float, col: Color, lean := 0.0, y0 := 0.0, glow := 0.0, lift := 0.006) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for s in [-1.0, 1.0]:
		for t in range(0, idx.size(), 3):
			var tri := []
			for k in 3:
				var p := poly[idx[t + k]]
				tri.append(Vector3(p.x, p.y, s * (hw - lean * (p.y - y0) + lift)))
			face(st, tri, col, Vector3(tri[0].x, tri[0].y, 0.0), glow)


## Glass on the face a cabin's prism builds on its profile edge a-b: inset `u` of its width each side and spanning v
## (fractions of the way from a to b), a little proud of the face.
static func edge_glass(st: SurfaceTool, a: Vector2, b: Vector2, hw: float, lean: float, y0: float, u: float, v: Vector2, inside: Vector3) -> void:
	var za := hw - lean * (a.y - y0)
	var zb := hw - lean * (b.y - y0)
	var q := [Vector3(a.x, a.y, -za), Vector3(a.x, a.y, za), Vector3(b.x, b.y, zb), Vector3(b.x, b.y, -zb)]
	var at := func(s: float, t: float) -> Vector3: return (q[0].lerp(q[1], s) as Vector3).lerp(q[3].lerp(q[2], s), t)
	var pts := [at.call(u, v.x), at.call(1.0 - u, v.x), at.call(1.0 - u, v.y), at.call(u, v.y)]
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
	n *= signf(n.dot(pts[0] - inside))
	face(st, pts.map(func(p: Vector3): return p + n * 0.006), GLASS, inside)


## A cabin's side windows: its profile drawn in by `frame` and cut off below `sill`, split into panes along x (each a
## range of x), on both sides.
static func side_glass(st: SurfaceTool, cab: PackedVector2Array, hw: float, lean: float, y0: float, frame: float, sill: float, panes: Array) -> void:
	var inner: PackedVector2Array = Geometry2D.offset_polygon(cab, -frame)[0]
	for p in panes:
		for g in Geometry2D.intersect_polygons(inner, rect(minf(p.x, p.y), sill, maxf(p.x, p.y), 9.0)):
			on_side(st, g, hw, GLASS, lean, y0)


## A number plate on the vehicle's front (facing +x, s 1) or back (s -1), its foot centred at at: 33 x 16.5 cm in its
## colour with a band of characters across it.
static func plate(st: SurfaceTool, at: Vector3, s: float, col: Color, ink: Color) -> void:
	box(st, at + Vector3(0, 0, -0.165), at + Vector3(s * 0.012, 0.165, 0.165), col)
	box(st, at + Vector3(s * 0.012, 0.05, -0.12), at + Vector3(s * 0.016, 0.11, 0.12), ink)
