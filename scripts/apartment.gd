class_name Apartment
extends Node3D
## L'appartement de Yannick (≈ 8 × 5,5 m), construit par code :
## murs avec ouvertures, sols, plafonds, meubles, verrière du salon, affiches, lumières.
## Géométrie fusionnée par pièce et par matériau → très peu d'appels de rendu.
##
## Repère : x vers la droite, z vers l'avant (entrée), y vers le haut. Unités = mètres.
##   Chambre  x[0;3,6]  z[0;3]      Salle de bain x[3,6;5,4] z[0;2,4]
##   Entrée   x[0;2,6]  z[3;5,5]    Salon-cuisine : le reste (kitchenette x[5,4;8] z[0;2,4])

const W := 8.0
const D := 5.5
const H_LOW := 2.5
const H_HIGH := 3.0
const T_OUT := 0.2
const T_IN := 0.12
const DOOR_H := 2.05

# verrière (ouverture dans le plafond du salon)
const GL_X0 := 3.9
const GL_X1 := 7.7
const GL_Z0 := 2.7
const GL_Z1 := 5.2

const C_WALL := Color("e7e0d3")
const C_CEIL := Color("f2eee6")
const C_WHITE := Color("f3f1ec")
const C_METAL := Color("a3a9ae")
const C_BLACK := Color("1c1e21")
const C_SAGE := Color("78968a")

const UVM := {"main": 1.0, "semi": 1.0, "wood": 1.2, "tile_l": 1.2, "tile_d": 0.9, "glow": 1.0}
const POSTERS := ["poster_1_derby", "poster_2_gardien", "poster_3_carte", "poster_4_finale",
		"poster_5_but", "poster_6_tactique", "poster_7_trophee", "poster_8_ballon"]

var batches := {}
var mats := {}
var wall_body: StaticBody3D   # couche 1 : murs + meubles hauts (bloquent joueur ET caméra)
var furn_body: StaticBody3D   # couche 2 : meubles bas (bloquent seulement le joueur)
var solids: Array = []        # [{min, max, cam}] pour les tests automatiques
var spawns := {
	"chambre": [Vector3(1.6, 0.05, 1.6), 0.0],
	"hall": [Vector3(1.3, 0.05, 4.2), 0.0],
	"sdb": [Vector3(4.65, 0.05, 1.5), 0.0],
	"salon": [Vector3(4.2, 0.05, 4.3), -PI / 2.0],
	"kitchen": [Vector3(6.8, 0.05, 1.3), 0.0],
	"verriere": [Vector3(5.8, 0.05, 3.9), 0.0],
}
var tv_mat: StandardMaterial3D


func build() -> void:
	wall_body = StaticBody3D.new()
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	add_child(wall_body)
	furn_body = StaticBody3D.new()
	furn_body.collision_layer = 2
	furn_body.collision_mask = 0
	add_child(furn_body)
	_make_mats()
	_build_environment()
	_build_walls()
	_build_floors_ceilings()
	_build_skylight()
	_build_chambre()
	_build_hall()
	_build_sdb()
	_build_salon()
	_flush_batches()
	_col(Vector3(-0.3, -0.6, -0.3), Vector3(W + 0.6, 0.6, D + 0.6), "wall")  # sol


## Vrai si la position est dans le salon-cuisine (zone éclairée par le jour de la verrière).
func is_open_space(p: Vector3) -> bool:
	if p.x >= 3.6 and p.z >= 2.4:
		return true
	if p.x >= 5.4 and p.z < 2.4:
		return true
	return p.x >= 2.6 and p.z >= 3.0


# ------------------------------------------------------------------ matériaux

func _tex(n: String) -> Texture2D:
	return load("res://assets/tex/%s.png" % n) as Texture2D


func _mat(t: Texture2D, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if t != null:
		m.albedo_texture = t
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = rough
	m.metallic = metal
	return m


func _make_mats() -> void:
	mats["main"] = _mat(_tex("grain"), 0.9, 0.0)
	mats["semi"] = _mat(_tex("grain"), 0.42, 0.12)
	mats["wood"] = _mat(_tex("parquet"), 0.5, 0.0)
	mats["tile_l"] = _mat(_tex("tile_light"), 0.3, 0.0)
	mats["tile_d"] = _mat(_tex("tile_dark"), 0.45, 0.0)
	var g := _mat(null, 1.0, 0.0)
	g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["glow"] = g
	tv_mat = StandardMaterial3D.new()
	tv_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tv_mat.albedo_texture = _tex("tvscreen")
	tv_mat.albedo_color = Color(0.92, 0.92, 0.92)


func _layers(room: String) -> int:
	return 3 if room == "salon" else 1


func _b(room: String, kind: String) -> MeshBatch:
	var k := room + "|" + kind
	if not batches.has(k):
		batches[k] = MeshBatch.new(UVM[kind])
	return batches[k] as MeshBatch


func _flush_batches() -> void:
	for k in batches.keys():
		var parts: PackedStringArray = String(k).split("|")
		var mi := (batches[k] as MeshBatch).build(mats[parts[1]] as Material, _layers(parts[0]))
		if mi != null:
			mi.name = "%s_%s" % [parts[0], parts[1]]
			add_child(mi)


# ------------------------------------------------------------------ primitives

func _col(p: Vector3, s: Vector3, solid: String) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	cs.position = p + s * 0.5
	if solid == "low":
		furn_body.add_child(cs)
	else:
		wall_body.add_child(cs)
	solids.append({"min": p, "max": p + s, "cam": solid != "low"})


## Boîte meublante : coin min (x,y,z), taille (sx,sy,sz), solid = "" | "low" | "tall" | "wall".
func _f(room: String, kind: String, x: float, y: float, z: float, sx: float, sy: float, sz: float,
		col: Color, solid: String = "") -> void:
	_b(room, kind).box(Vector3(x, y, z), Vector3(sx, sy, sz), col)
	if solid != "":
		_col(Vector3(x, y, z), Vector3(sx, sy, sz), solid)


func _cyl(room: String, kind: String, x: float, y: float, z: float, r: float, h: float, col: Color, sides: int = 8) -> void:
	_b(room, kind).prism(Vector3(x, y, z), r, h, col, sides)


func _omni(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	add_child(l)


# ------------------------------------------------------------------ environnement

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9cc6ee")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1de")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ murs

func _wall(a: Vector2, b: Vector2, h: float, t: float, room: String, openings: Array = []) -> void:
	var along_x := is_equal_approx(a.y, b.y)
	var length := (b - a).length()
	var s := 0.0
	for o in openings:
		if float(o[0]) > s:
			_wall_seg(a, along_x, s, float(o[0]), 0.0, h, t, room)
		_wall_seg(a, along_x, float(o[0]), float(o[1]), DOOR_H, h - DOOR_H, t, room)   # linteau
		_door_trim(a, along_x, float(o[0]), float(o[1]), t, room)
		s = float(o[1])
	if s < length - 0.001:
		_wall_seg(a, along_x, s, length, 0.0, h, t, room)


func _wall_seg(a: Vector2, along_x: bool, s0: float, s1: float, y0: float, hh: float, t: float, room: String) -> void:
	var p: Vector3
	var sz: Vector3
	if along_x:
		p = Vector3(a.x + s0, y0, a.y - t * 0.5)
		sz = Vector3(s1 - s0, hh, t)
	else:
		p = Vector3(a.x - t * 0.5, y0, a.y + s0)
		sz = Vector3(t, hh, s1 - s0)
	_f(room, "main", p.x, p.y, p.z, sz.x, sz.y, sz.z, C_WALL, "wall")
	if y0 == 0.0:   # plinthes des deux côtés
		var e := 0.012
		if along_x:
			_f(room, "main", p.x, 0.0, p.z - e, sz.x, 0.09, e, C_WHITE)
			_f(room, "main", p.x, 0.0, p.z + t, sz.x, 0.09, e, C_WHITE)
		else:
			_f(room, "main", p.x - e, 0.0, p.z, e, 0.09, sz.z, C_WHITE)
			_f(room, "main", p.x + t, 0.0, p.z, e, 0.09, sz.z, C_WHITE)


func _door_trim(a: Vector2, along_x: bool, s0: float, s1: float, t: float, room: String) -> void:
	var tt := t + 0.02
	if along_x:
		_f(room, "main", a.x + s0, 0.0, a.y - tt * 0.5, 0.05, DOOR_H, tt, C_WHITE)
		_f(room, "main", a.x + s1 - 0.05, 0.0, a.y - tt * 0.5, 0.05, DOOR_H, tt, C_WHITE)
		_f(room, "main", a.x + s0, DOOR_H - 0.05, a.y - tt * 0.5, s1 - s0, 0.05, tt, C_WHITE)
	else:
		_f(room, "main", a.x - tt * 0.5, 0.0, a.y + s0, tt, DOOR_H, 0.05, C_WHITE)
		_f(room, "main", a.x - tt * 0.5, 0.0, a.y + s1 - 0.05, tt, DOOR_H, 0.05, C_WHITE)
		_f(room, "main", a.x - tt * 0.5, DOOR_H - 0.05, a.y + s0, tt, 0.05, s1 - s0, C_WHITE)


func _build_walls() -> void:
	# murs extérieurs
	_wall(Vector2(0, 0), Vector2(5.4, 0), H_LOW, T_OUT, "chambre")
	_wall(Vector2(5.4, 0), Vector2(8, 0), H_HIGH, T_OUT, "salon")
	_wall(Vector2(8, 0), Vector2(8, 5.5), H_HIGH, T_OUT, "salon")
	_wall(Vector2(0, 5.5), Vector2(2.6, 5.5), H_LOW, T_OUT, "hall")
	_wall(Vector2(2.6, 5.5), Vector2(8, 5.5), H_HIGH, T_OUT, "salon")
	_wall(Vector2(0, 0), Vector2(0, 3.0), H_LOW, T_OUT, "chambre")
	_wall(Vector2(0, 3.0), Vector2(0, 5.5), H_LOW, T_OUT, "hall")
	# cloisons (ouvertures : porte de chambre 0,9 m, passage d'entrée 1,1 m, porte de salle de bain 0,8 m)
	_wall(Vector2(3.6, 0), Vector2(3.6, 2.4), H_LOW, T_IN, "chambre")
	_wall(Vector2(3.6, 2.4), Vector2(3.6, 3.0), H_HIGH, T_IN, "salon")
	_wall(Vector2(0, 3.0), Vector2(2.6, 3.0), H_LOW, T_IN, "hall", [[1.1, 2.0]])
	_wall(Vector2(2.6, 3.0), Vector2(3.6, 3.0), H_HIGH, T_IN, "salon")
	_wall(Vector2(2.6, 3.0), Vector2(2.6, 5.5), H_HIGH, T_IN, "salon", [[0.8, 1.9]])
	_wall(Vector2(3.6, 2.4), Vector2(5.4, 2.4), H_HIGH, T_IN, "salon", [[0.6, 1.5]])
	_wall(Vector2(5.4, 0), Vector2(5.4, 2.4), H_HIGH, T_IN, "salon")


# ------------------------------------------------------------------ sols, plafonds

func _floor(room: String, kind: String, x0: float, z0: float, x1: float, z1: float) -> void:
	_b(room, kind).box(Vector3(x0, -0.1, z0), Vector3(x1 - x0, 0.1, z1 - z0), Color.WHITE)


func _ceil(room: String, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	_f(room, "main", x0, y, z0, x1 - x0, 0.05, z1 - z0, C_CEIL, "wall")


func _build_floors_ceilings() -> void:
	_floor("chambre", "wood", -0.1, -0.1, 3.6, 3.0)
	_floor("hall", "tile_d", -0.1, 3.0, 2.6, 5.6)
	_floor("sdb", "tile_l", 3.6, -0.1, 5.4, 2.4)
	_floor("salon", "tile_d", 5.4, -0.1, 8.1, 2.4)
	_floor("salon", "wood", 3.6, 2.4, 8.1, 5.6)
	_floor("salon", "wood", 2.6, 3.0, 3.6, 5.6)
	# plafonds classiques à 2,5 m
	_ceil("chambre", -0.1, -0.1, 3.6, 3.0, H_LOW)
	_ceil("sdb", 3.6, -0.1, 5.4, 2.4, H_LOW)
	_ceil("hall", -0.1, 3.0, 2.6, 5.6, H_LOW)
	# salon-cuisine à 3 m : anneau autour de la verrière + kitchenette
	_ceil("salon", 5.4, -0.1, 8.1, 2.4, H_HIGH)
	_ceil("salon", 3.6, 2.4, 8.1, GL_Z0, H_HIGH)
	_ceil("salon", 3.6, GL_Z1, 8.1, 5.6, H_HIGH)
	_ceil("salon", 3.6, GL_Z0, GL_X0, GL_Z1, H_HIGH)
	_ceil("salon", GL_X1, GL_Z0, 8.1, GL_Z1, H_HIGH)
	_ceil("salon", 2.6, 3.0, 3.6, 5.6, H_HIGH)
	# dalle invisible au-dessus de la verrière : empêche la caméra de sortir par le toit
	_col(Vector3(GL_X0, H_HIGH, GL_Z0), Vector3(GL_X1 - GL_X0, 0.05, GL_Z1 - GL_Z0), "wall")


# ------------------------------------------------------------------ verrière

func _build_skylight() -> void:
	var cols := 4
	var rows := 3
	var fy := H_HIGH - 0.07
	for i in cols + 1:
		var x := GL_X0 + (GL_X1 - GL_X0) * float(i) / float(cols)
		_f("salon", "semi", x - 0.03, fy, GL_Z0 - 0.03, 0.06, 0.09, GL_Z1 - GL_Z0 + 0.06, C_BLACK)
	for j in rows + 1:
		var z := GL_Z0 + (GL_Z1 - GL_Z0) * float(j) / float(rows)
		_f("salon", "semi", GL_X0 - 0.03, fy, z - 0.03, GL_X1 - GL_X0 + 0.06, 0.09, 0.06, C_BLACK)
	# vitres : un seul maillage, un seul matériau translucide très léger
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cw := (GL_X1 - GL_X0) / float(cols)
	var rh := (GL_Z1 - GL_Z0) / float(rows)
	var gy := H_HIGH - 0.02
	for i in cols:
		for j in rows:
			var x0 := GL_X0 + cw * i
			var z0 := GL_Z0 + rh * j
			var q := [Vector3(x0, gy, z0), Vector3(x0 + cw, gy, z0), Vector3(x0 + cw, gy, z0 + rh), Vector3(x0, gy, z0 + rh)]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.DOWN)
				st.set_uv(uv[k])
				st.add_vertex(q[k])
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = _tex("glass")
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var glass := MeshInstance3D.new()
	glass.name = "verriere_vitres"
	glass.mesh = st.commit()
	glass.material_override = gm
	add_child(glass)
	# ciel : dôme non éclairé, visible à travers la verrière et les fenêtres
	var sphere := SphereMesh.new()
	sphere.radius = 40.0
	sphere.height = 80.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = _tex("sky")
	sm.cull_mode = BaseMaterial3D.CULL_FRONT
	var dome := MeshInstance3D.new()
	dome.name = "ciel"
	dome.mesh = sphere
	dome.material_override = sm
	dome.position = Vector3(5.8, 0.0, 4.0)
	add_child(dome)
	# lumière du jour : un spot (sans ombres) limité au salon par les couches de rendu
	var sun := SpotLight3D.new()
	sun.name = "soleil_verriere"
	sun.position = Vector3(5.8, 6.0, 3.95)
	sun.rotation_degrees = Vector3(-90, 0, 0)
	sun.spot_range = 9.0
	sun.spot_angle = 30.0
	sun.spot_angle_attenuation = 0.8
	sun.light_energy = 1.7
	sun.light_color = Color("fff0d4")
	sun.light_cull_mask = 2
	sun.light_projector = _tex("projector")
	add_child(sun)


# ------------------------------------------------------------------ affiches

func _poster(room: String, idx: int, c: Vector3, rot_deg: float) -> void:
	var t := load("res://assets/posters/%s.png" % POSTERS[idx]) as Texture2D
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.825)
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.roughness = 0.8
	m.emission_enabled = true
	m.emission_texture = t
	m.emission_energy_multiplier = 0.22
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.name = "affiche_%d" % (idx + 1)
	mi.mesh = q
	mi.material_override = m
	mi.position = c
	mi.rotation_degrees = Vector3(0, rot_deg, 0)
	mi.layers = _layers(room)
	add_child(mi)
	var n := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(rot_deg))
	var fc := c - n * 0.007
	var sz := Vector3(0.6, 0.875, 0.012) if absf(n.z) > 0.5 else Vector3(0.012, 0.875, 0.6)
	_f(room, "semi", fc.x - sz.x * 0.5, fc.y - sz.y * 0.5, fc.z - sz.z * 0.5, sz.x, sz.y, sz.z, Color("202020"))


func _screen(room: String, c: Vector3, size: Vector2, rot_deg: float) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = tv_mat
	mi.position = c
	mi.rotation_degrees = Vector3(0, rot_deg, 0)
	mi.layers = _layers(room)
	add_child(mi)


func _ball(room: String, c: Vector3) -> void:
	var s := SphereMesh.new()
	s.radius = 0.11
	s.height = 0.22
	s.radial_segments = 12
	s.rings = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ecebe6")
	m.roughness = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.position = c
	mi.layers = _layers(room)
	add_child(mi)


func _window(room: String, x0: float, y0: float, x1: float, y1: float, z: float) -> void:
	_f(room, "glow", x0 + 0.03, y0 + 0.04, z, x1 - x0 - 0.06, y1 - y0 - 0.08, 0.012, Color("c4e2ff"))
	_f(room, "main", x0, y1 - 0.04, z, x1 - x0, 0.04, 0.035, C_WHITE)
	_f(room, "main", x0, y0, z, x1 - x0, 0.04, 0.035, C_WHITE)
	_f(room, "main", x0, y0, z, 0.03, y1 - y0, 0.035, C_WHITE)
	_f(room, "main", x1 - 0.03, y0, z, 0.03, y1 - y0, 0.035, C_WHITE)
	_f(room, "main", (x0 + x1) * 0.5 - 0.01, y0, z, 0.02, y1 - y0, 0.03, C_WHITE)
	_f(room, "main", x0 - 0.04, y0 - 0.03, z, x1 - x0 + 0.08, 0.03, 0.09, C_WHITE)


# ------------------------------------------------------------------ chambre

func _build_chambre() -> void:
	var R := "chambre"
	var pine := Color("b8925f")
	var pine_d := Color("9a7647")
	# accent mural gris-bleu côté bureau
	_f(R, "main", 0.1, 0.0, 0.1, 3.5, 2.5, 0.008, Color("9ba7ad"))
	# lit superposé (x 0,12-1,06 / z 0,12-2,17)
	for px in [0.12, 0.96]:
		for pz in [0.12, 2.11]:
			_f(R, "main", px, 0.0, pz, 0.06, 1.8, 0.06, pine)
	_f(R, "main", 0.12, 0.30, 0.12, 0.90, 0.04, 2.05, pine_d)
	_f(R, "main", 0.12, 1.15, 0.12, 0.90, 0.04, 2.05, pine_d)
	_f(R, "main", 0.15, 0.34, 0.15, 0.84, 0.20, 1.99, Color("6f7f92"))
	_f(R, "main", 0.15, 1.19, 0.15, 0.84, 0.20, 1.99, Color("7f8f7a"))
	_f(R, "main", 0.25, 0.54, 0.2, 0.55, 0.10, 0.32, Color("e9e6df"))
	_f(R, "main", 0.25, 1.39, 0.2, 0.55, 0.10, 0.32, Color("e4e0d6"))
	_f(R, "main", 0.17, 0.54, 0.75, 0.80, 0.08, 0.95, Color("2f3e55"))
	_f(R, "main", 0.22, 0.62, 1.15, 0.45, 0.05, 0.5, Color("2f3e55"))
	_f(R, "main", 0.17, 1.39, 0.8, 0.8, 0.07, 1.0, Color("8a5a44"))
	_f(R, "main", 0.3, 1.46, 1.88, 0.4, 0.06, 0.25, Color("c9c5bc"))
	_f(R, "main", 0.94, 1.45, 0.12, 0.04, 0.05, 1.45, pine)
	_f(R, "main", 0.12, 1.45, 0.12, 0.90, 0.05, 0.04, pine)
	for lz in [1.72, 2.06]:
		_f(R, "main", 1.02, 0.12, lz, 0.04, 1.45, 0.04, pine)
	for ly in [0.35, 0.65, 0.95, 1.25]:
		_f(R, "main", 1.02, ly, 1.72, 0.04, 0.04, 0.38, pine)
	_col(Vector3(0.12, 0.0, 0.12), Vector3(0.94, 1.8, 2.05), "tall")
	# bureau
	var wd := Color("6b4a33")
	_f(R, "main", 1.5, 0.72, 0.1, 1.35, 0.04, 0.6, wd)
	_f(R, "main", 1.5, 0.0, 0.1, 0.04, 0.72, 0.6, wd)
	_f(R, "main", 2.81, 0.0, 0.1, 0.04, 0.72, 0.6, wd)
	_col(Vector3(1.5, 0.0, 0.1), Vector3(1.35, 0.76, 0.6), "low")
	_f(R, "semi", 1.98, 0.76, 0.28, 0.14, 0.03, 0.14, C_BLACK)
	_f(R, "semi", 2.03, 0.79, 0.33, 0.04, 0.15, 0.04, C_BLACK)
	_f(R, "semi", 1.78, 0.93, 0.34, 0.56, 0.33, 0.03, C_BLACK)
	_screen(R, Vector3(2.06, 1.095, 0.373), Vector2(0.5, 0.28), 0.0)
	_f(R, "semi", 1.85, 0.76, 0.5, 0.42, 0.02, 0.14, C_BLACK)
	_f(R, "semi", 2.35, 0.76, 0.52, 0.06, 0.03, 0.1, C_BLACK)
	_f(R, "semi", 1.58, 0.76, 0.3, 0.18, 0.12, 0.18, Color("2a2d31"))
	_f(R, "semi", 1.6, 0.76, 0.52, 0.15, 0.04, 0.1, Color("3a3d42"))
	_cyl(R, "semi", 2.62, 0.76, 0.5, 0.04, 0.09, Color("efefea"), 8)
	# chaise de bureau
	_f(R, "main", 2.0, 0.44, 0.95, 0.46, 0.06, 0.46, Color("2a2d31"))
	_f(R, "main", 2.0, 0.5, 1.37, 0.46, 0.45, 0.05, Color("2a2d31"))
	_cyl(R, "semi", 2.23, 0.0, 1.18, 0.035, 0.44, C_METAL, 6)
	_f(R, "main", 1.95, 0.0, 1.15, 0.56, 0.04, 0.06, C_BLACK)
	_f(R, "main", 2.18, 0.0, 0.93, 0.06, 0.04, 0.5, C_BLACK)
	_col(Vector3(1.95, 0.0, 0.93), Vector3(0.56, 0.95, 0.52), "low")
	# armoire
	_f(R, "main", 2.95, 0.0, 1.0, 0.55, 1.95, 1.0, Color("e6e2d8"), "tall")
	_f(R, "semi", 2.944, 0.05, 1.49, 0.006, 1.85, 0.02, Color("a9a396"))
	_f(R, "semi", 2.935, 0.95, 1.43, 0.015, 0.2, 0.02, C_METAL)
	_f(R, "semi", 2.935, 0.95, 1.55, 0.015, 0.2, 0.02, C_METAL)
	# sol habité : tapis, vêtements, baskets, carton, pizza, ballon
	_f(R, "main", 1.15, 0.0, 1.35, 1.6, 0.012, 1.05, Color("56646b"))
	_f(R, "main", 1.3, 0.012, 1.7, 0.4, 0.03, 0.3, Color("3c5a8a"))
	_f(R, "main", 1.9, 0.012, 2.0, 0.3, 0.05, 0.6, Color("2b3b57"))
	_f(R, "main", 1.95, 0.062, 2.1, 0.25, 0.04, 0.3, Color("2b3b57"))
	_f(R, "main", 1.6, 0.012, 2.4, 0.1, 0.03, 0.18, Color("d8d8d4"))
	_f(R, "main", 1.2, 0.0, 2.45, 0.3, 0.1, 0.12, Color("e8e8e4"))
	_f(R, "main", 1.25, 0.0, 2.62, 0.3, 0.1, 0.12, Color("c6403f"))
	_f(R, "main", 2.55, 0.0, 2.35, 0.45, 0.32, 0.4, Color("b08a5a"), "low")
	_f(R, "main", 2.15, 0.012, 1.9, 0.34, 0.04, 0.34, Color("c9a46a"))
	_ball(R, Vector3(1.75, 0.11, 2.6))
	# fenêtre côté lit (le ciel s'y voit)
	_window(R, 0.17, 1.21, 0.98, 2.09, 0.1)
	# affiches de foot au-dessus du bureau
	_poster(R, 0, Vector3(1.7, 1.55, 0.112), 0.0)
	_poster(R, 1, Vector3(2.4, 1.55, 0.112), 0.0)
	_poster(R, 2, Vector3(3.1, 1.55, 0.112), 0.0)
	# plafonnier + lumière froide de fenêtre
	_cyl(R, "glow", 1.8, 2.44, 1.5, 0.18, 0.05, Color("fff3dc"), 12)
	_omni(Vector3(1.8, 2.1, 1.5), Color("fff0d8"), 0.85, 4.6)
	_omni(Vector3(0.7, 1.7, 0.7), Color("cfe6ff"), 0.35, 2.6)


# ------------------------------------------------------------------ entrée

func _build_hall() -> void:
	var R := "hall"
	# porte d'entrée (fermée, décorative) dans le mur de façade z = 5,4
	var dc := Color("5b4636")
	_f(R, "main", 0.7, 0.0, 5.345, 0.9, 2.05, 0.055, dc)
	_f(R, "main", 0.8, 1.15, 5.333, 0.7, 0.75, 0.012, Color("6a5440"))
	_f(R, "main", 0.8, 0.2, 5.333, 0.7, 0.8, 0.012, Color("6a5440"))
	_f(R, "main", 0.65, 0.0, 5.33, 0.05, 2.1, 0.07, C_WHITE)
	_f(R, "main", 1.6, 0.0, 5.33, 0.05, 2.1, 0.07, C_WHITE)
	_f(R, "main", 0.65, 2.05, 5.33, 1.0, 0.05, 0.07, C_WHITE)
	_f(R, "semi", 1.45, 1.0, 5.31, 0.12, 0.025, 0.04, C_METAL)
	_f(R, "semi", 1.15, 1.55, 5.325, 0.03, 0.03, 0.02, C_BLACK)
	_f(R, "main", 0.6, 0.0, 4.95, 1.0, 0.015, 0.35, Color("2d2d2d"))
	# meuble à chaussures
	_f(R, "main", 1.75, 0.0, 5.1, 0.7, 0.5, 0.3, Color("d9d2c4"), "low")
	_f(R, "main", 1.85, 0.5, 5.15, 0.28, 0.1, 0.12, Color("1f2a44"))
	_f(R, "main", 2.15, 0.5, 5.15, 0.26, 0.09, 0.12, Color("d9d9d4"))
	# patère et manteaux
	_f(R, "main", 0.1, 1.65, 3.35, 0.05, 0.08, 0.7, Color("7a5a3d"))
	_f(R, "main", 0.15, 0.95, 3.4, 0.1, 0.7, 0.28, Color("3b4a5a"))
	_f(R, "main", 0.15, 0.95, 3.72, 0.1, 0.65, 0.26, Color("8a8d90"))
	# affiches
	_poster(R, 6, Vector3(0.112, 1.55, 4.5), 90.0)
	_poster(R, 4, Vector3(0.55, 1.55, 3.072), 0.0)
	_cyl(R, "glow", 1.3, 2.44, 4.2, 0.16, 0.05, Color("fff3dc"), 12)
	_omni(Vector3(1.3, 2.15, 4.2), Color("fff0d8"), 0.7, 3.8)


# ------------------------------------------------------------------ salle de bain

func _build_sdb() -> void:
	var R := "sdb"
	var white := Color("f2f2ef")
	# faïence murale
	_f(R, "tile_l", 3.66, 0.0, 0.1, 1.68, 1.5, 0.008, Color.WHITE)
	_f(R, "tile_l", 3.66, 0.0, 0.108, 0.008, 1.5, 2.232, Color.WHITE)
	_f(R, "tile_l", 5.332, 0.0, 0.108, 0.008, 1.5, 2.232, Color.WHITE)
	# douche
	_f(R, "semi", 4.5, 0.0, 0.1, 0.84, 0.08, 0.82, Color("eeeeee"))
	_f(R, "semi", 4.5, 0.08, 0.9, 0.03, 1.92, 0.03, C_METAL)
	_f(R, "semi", 4.5, 0.08, 0.1, 0.03, 1.92, 0.03, C_METAL)
	_f(R, "semi", 5.31, 0.08, 0.9, 0.03, 1.92, 0.03, C_METAL)
	_f(R, "semi", 4.5, 2.0, 0.1, 0.03, 0.03, 0.82, C_METAL)
	_f(R, "semi", 4.5, 2.0, 0.9, 0.84, 0.03, 0.03, C_METAL)
	_f(R, "semi", 5.2, 1.95, 0.1, 0.03, 0.03, 0.2, C_METAL)
	_f(R, "semi", 5.22, 1.0, 0.1, 0.02, 0.95, 0.02, C_METAL)
	_col(Vector3(4.5, 0.0, 0.1), Vector3(0.84, 2.0, 0.82), "tall")
	# WC
	_f(R, "semi", 3.78, 0.5, 0.1, 0.34, 0.4, 0.2, white)
	_f(R, "semi", 3.78, 0.0, 0.3, 0.34, 0.4, 0.42, white)
	_f(R, "semi", 3.76, 0.4, 0.3, 0.38, 0.04, 0.44, Color("efefec"))
	_col(Vector3(3.75, 0.0, 0.1), Vector3(0.4, 0.95, 0.62), "low")
	# meuble vasque + miroir
	_f(R, "main", 3.66, 0.0, 1.0, 0.45, 0.78, 0.75, Color("d8d1c4"))
	_f(R, "semi", 3.66, 0.78, 1.0, 0.47, 0.03, 0.77, Color("e8e8e6"))
	_f(R, "semi", 3.7, 0.81, 1.2, 0.3, 0.005, 0.35, Color("c9ced2"))
	_cyl(R, "semi", 3.75, 0.81, 1.375, 0.012, 0.15, C_METAL, 6)
	_f(R, "semi", 3.75, 0.94, 1.365, 0.12, 0.02, 0.02, C_METAL)
	_col(Vector3(3.66, 0.0, 1.0), Vector3(0.47, 0.82, 0.77), "low")
	_f(R, "semi", 3.664, 1.15, 1.05, 0.01, 0.8, 0.65, Color("b6c2ca"))
	_f(R, "glow", 3.664, 1.97, 1.1, 0.04, 0.03, 0.55, Color("fff4e0"))
	# panier à linge, tapis, serviette
	_cyl(R, "main", 5.0, 0.0, 1.9, 0.2, 0.55, Color("b79f78"), 10)
	_col(Vector3(4.8, 0.0, 1.7), Vector3(0.4, 0.55, 0.4), "low")
	_f(R, "main", 4.35, 0.0, 1.4, 0.7, 0.015, 0.5, Color("c8d3d8"))
	_f(R, "main", 5.28, 1.1, 1.2, 0.05, 0.55, 0.3, Color("5a8fa6"))
	_omni(Vector3(4.5, 2.1, 1.2), Color("fffaf0"), 0.75, 3.2)


# ------------------------------------------------------------------ salon + cuisine

func _build_salon() -> void:
	var R := "salon"
	var sage := C_SAGE
	# mur d'accent derrière la télé
	_f(R, "main", 7.89, 0.0, 2.4, 0.01, 3.0, 3.0, Color("4f666b"))
	# canapé (face à la télé)
	var sofa := Color("4a5560")
	_f(R, "main", 5.2, 0.12, 3.3, 0.85, 0.33, 2.0, sofa)
	_f(R, "main", 5.2, 0.45, 3.3, 0.2, 0.45, 2.0, sofa)
	_f(R, "main", 5.2, 0.45, 3.3, 0.85, 0.17, 0.2, sofa)
	_f(R, "main", 5.2, 0.45, 5.1, 0.85, 0.17, 0.2, sofa)
	_f(R, "main", 5.4, 0.45, 3.5, 0.6, 0.10, 0.8, Color("56626d"))
	_f(R, "main", 5.4, 0.45, 4.3, 0.6, 0.10, 0.8, Color("56626d"))
	_f(R, "main", 5.45, 0.55, 3.55, 0.12, 0.35, 0.35, Color("c27a3d"))
	_f(R, "main", 5.5, 0.55, 4.5, 0.4, 0.05, 0.6, Color("8a8f93"))
	for lz in [3.35, 5.15]:
		_f(R, "main", 5.25, 0.0, lz, 0.05, 0.12, 0.05, C_BLACK)
		_f(R, "main", 5.95, 0.0, lz, 0.05, 0.12, 0.05, C_BLACK)
	_col(Vector3(5.2, 0.0, 3.3), Vector3(0.85, 0.9, 2.0), "low")
	# table basse + objets
	_f(R, "main", 6.45, 0.38, 3.8, 0.6, 0.04, 1.0, Color("6e5038"))
	_f(R, "main", 6.45, 0.12, 3.8, 0.6, 0.03, 1.0, Color("5a4330"))
	for tx in [6.5, 6.93]:
		for tz in [3.85, 4.73]:
			_f(R, "main", tx, 0.0, tz, 0.04, 0.38, 0.04, Color("5a4330"))
	_col(Vector3(6.45, 0.0, 3.8), Vector3(0.6, 0.42, 1.0), "low")
	_f(R, "semi", 6.6, 0.42, 4.0, 0.15, 0.03, 0.1, Color("2a2d31"))
	_f(R, "semi", 6.8, 0.42, 4.5, 0.05, 0.015, 0.16, C_BLACK)
	_cyl(R, "semi", 6.7, 0.42, 4.25, 0.033, 0.12, Color("c0392b"), 8)
	_cyl(R, "semi", 6.85, 0.42, 4.35, 0.033, 0.12, C_METAL, 8)
	# meuble TV, télé, console, enseigne
	_f(R, "main", 7.5, 0.0, 3.6, 0.4, 0.45, 1.4, Color("3a2f28"), "low")
	_f(R, "semi", 7.7, 0.45, 4.05, 0.14, 0.17, 0.4, C_BLACK)
	_f(R, "semi", 7.83, 0.6, 3.75, 0.05, 0.65, 1.1, C_BLACK)
	_screen(R, Vector3(7.8, 0.925, 4.3), Vector2(1.04, 0.585), -90.0)
	_f(R, "semi", 7.55, 0.45, 4.55, 0.3, 0.07, 0.4, Color("1d1f22"))
	_f(R, "glow", 7.56, 0.5, 4.54, 0.02, 0.01, 0.1, Color("4aa8ff"))
	var neon := StandardMaterial3D.new()
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon.albedo_texture = _tex("neon_pta")
	var nq := QuadMesh.new()
	nq.size = Vector2(1.2, 0.6)
	var nmi := MeshInstance3D.new()
	nmi.name = "enseigne_PTA"
	nmi.mesh = nq
	nmi.material_override = neon
	nmi.position = Vector3(7.885, 2.1, 4.3)
	nmi.rotation_degrees = Vector3(0, -90, 0)
	nmi.layers = 3
	add_child(nmi)
	_omni(Vector3(7.1, 0.95, 4.3), Color("9fc4ff"), 0.45, 2.6)
	# bibliothèque
	var bw := Color("7a5a3d")
	_f(R, "main", 6.2, 0.0, 5.38, 1.0, 1.85, 0.02, Color("5a4330"))
	_f(R, "main", 6.2, 0.0, 5.1, 0.03, 1.85, 0.3, bw)
	_f(R, "main", 7.17, 0.0, 5.1, 0.03, 1.85, 0.3, bw)
	_f(R, "main", 6.2, 1.85, 5.1, 1.0, 0.03, 0.3, bw)
	var palette := [Color("a33b3b"), Color("3b5fa3"), Color("d6b04a"), Color("4e7d57"), Color("e0dccf"), Color("5b3f7a"), Color("2f2f33")]
	for s in 5:
		var sy := 0.05 + 0.4 * s
		_f(R, "main", 6.2, sy, 5.1, 1.0, 0.025, 0.3, bw)
		var bx := 6.24
		for i in 11:
			var rnd := fposmod(sin(float(i) * 12.9898 + float(s) * 78.233) * 43758.5453, 1.0)
			var bh := 0.2 + 0.12 * rnd
			var bwid := 0.035 + 0.025 * fposmod(rnd * 7.0, 1.0)
			if bx + bwid > 7.15:
				break
			_f(R, "main", bx, sy + 0.025, 5.16, bwid, bh, 0.2, palette[(i + s * 3) % palette.size()])
			bx += bwid + 0.004
	_col(Vector3(6.2, 0.0, 5.1), Vector3(1.0, 1.88, 0.3), "tall")
	# plante
	_cyl(R, "main", 7.6, 0.0, 5.15, 0.15, 0.3, Color("a85a3b"), 10)
	_cyl(R, "main", 7.6, 0.3, 5.15, 0.21, 0.35, Color("3d6b3a"), 9)
	_cyl(R, "main", 7.6, 0.6, 5.15, 0.15, 0.3, Color("4b7d43"), 8)
	_cyl(R, "main", 7.6, 0.85, 5.15, 0.08, 0.2, Color("5a8c4d"), 7)
	_col(Vector3(7.43, 0.0, 4.98), Vector3(0.34, 1.1, 0.34), "low")
	# lampadaire
	_cyl(R, "semi", 4.6, 0.0, 5.0, 0.14, 0.03, C_BLACK, 10)
	_cyl(R, "semi", 4.6, 0.03, 5.0, 0.015, 1.55, C_BLACK, 6)
	_cyl(R, "glow", 4.6, 1.35, 5.0, 0.16, 0.3, Color("ffe2b0"), 12)
	_col(Vector3(4.45, 0.0, 4.85), Vector3(0.3, 1.65, 0.3), "low")
	_omni(Vector3(4.6, 1.65, 5.0), Color("ffd9a8"), 0.9, 3.4)
	# affiches
	_poster(R, 3, Vector3(3.0, 1.55, 5.388), 180.0)
	_poster(R, 5, Vector3(3.7, 1.55, 5.388), 180.0)
	_poster(R, 7, Vector3(3.672, 1.55, 2.72), 90.0)
	_build_kitchen(R, sage)


func _build_kitchen(R: String, sage: Color) -> void:
	var top := Color("c9c3b6")
	# frigo
	_f(R, "semi", 5.5, 0.0, 0.1, 0.6, 1.85, 0.65, Color("d9dcdf"), "tall")
	_f(R, "semi", 5.5, 1.25, 0.745, 0.6, 0.008, 0.008, Color("9a9ea3"))
	_f(R, "semi", 5.54, 0.5, 0.75, 0.02, 0.9, 0.03, C_BLACK)
	# plan de travail principal
	_f(R, "main", 6.1, 0.0, 0.1, 1.8, 0.86, 0.6, sage, "low")
	_f(R, "main", 6.1, 0.86, 0.1, 1.8, 0.04, 0.62, top)
	for i in range(1, 4):
		_f(R, "semi", 6.1 + 0.45 * i, 0.05, 0.7, 0.008, 0.78, 0.01, Color("55705f"))
	_f(R, "semi", 6.5, 0.895, 0.2, 0.5, 0.008, 0.4, C_METAL)
	_cyl(R, "semi", 6.75, 0.9, 0.2, 0.012, 0.2, C_METAL, 6)
	_f(R, "semi", 7.2, 0.9, 0.2, 0.5, 0.01, 0.4, C_BLACK)
	for hx in [7.32, 7.58]:
		for hz in [0.3, 0.52]:
			_cyl(R, "semi", hx, 0.91, hz, 0.06, 0.006, Color("3b3e42"), 10)
	_cyl(R, "semi", 7.32, 0.91, 0.3, 0.09, 0.12, Color("8a8f94"), 10)
	_f(R, "tile_l", 6.1, 0.9, 0.1, 1.8, 0.6, 0.008, Color.WHITE)
	_f(R, "main", 6.1, 1.5, 0.1, 1.8, 0.7, 0.34, Color("8aa597"))
	# plan latéral
	_f(R, "main", 7.3, 0.0, 0.7, 0.6, 0.86, 1.0, sage, "low")
	_f(R, "main", 7.3, 0.86, 0.7, 0.6, 0.04, 1.0, top)
	# bar
	_f(R, "main", 5.6, 0.0, 1.55, 0.8, 1.0, 0.45, sage, "low")
	_f(R, "main", 5.56, 1.0, 1.51, 0.88, 0.05, 0.53, Color("9a7b57"))
	_cyl(R, "semi", 6.2, 1.05, 1.75, 0.1, 0.05, Color("c9a063"), 10)
	_cyl(R, "semi", 5.8, 1.05, 1.8, 0.04, 0.09, Color("efefea"), 8)
	# tabourets
	for sx in [5.85, 6.25]:
		_cyl(R, "semi", sx, 0.0, 2.25, 0.025, 0.62, C_METAL, 6)
		_cyl(R, "semi", sx, 0.62, 2.25, 0.17, 0.04, Color("2c2c2c"), 10)
		_col(Vector3(sx - 0.17, 0.0, 2.08), Vector3(0.34, 0.66, 0.34), "low")
	# vaisselle qui traîne
	_cyl(R, "semi", 6.35, 0.9, 0.35, 0.12, 0.04, Color("efefea"), 10)
	_cyl(R, "semi", 6.62, 0.9, 0.3, 0.07, 0.03, Color("d9d4c8"), 8)
	_f(R, "main", 6.15, 0.9, 0.15, 0.28, 0.02, 0.22, Color("b08a5a"))
	_cyl(R, "semi", 7.78, 0.9, 0.25, 0.04, 0.1, Color("3e6aa8"), 8)
	_omni(Vector3(6.8, 2.7, 1.3), Color("fff4e4"), 0.7, 3.6)
