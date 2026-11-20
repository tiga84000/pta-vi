class_name MeshBatch
extends RefCounted
## Accumule des boîtes / prismes colorés (couleur par sommet) dans UN seul maillage.
## Un maillage par pièce et par matériau = très peu d'appels de rendu sur iPhone.
## Les UV sont projetés en coordonnées monde (1 texture = uv_meters mètres).

var st := SurfaceTool.new()
var uv_m := 1.0
var count := 0


func _init(uv_meters: float = 1.0) -> void:
	uv_m = uv_meters
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func _uv(v: Vector3, n: Vector3) -> Vector2:
	if absf(n.x) > 0.5:
		return Vector2(v.z, -v.y) / uv_m
	if absf(n.y) > 0.5:
		return Vector2(v.x, v.z) / uv_m
	return Vector2(v.x, -v.y) / uv_m


func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot : face avant = sens horaire. cross(b-a, c-a) doit être opposé à la normale.
	var order := [a, b, c]
	if (b - a).cross(c - a).dot(n) > 0.0:
		order = [a, c, b]
	for v in order:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(_uv(v, n))
		st.add_vertex(v)


func _face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(a, b, c, n, col)
	_tri(a, c, d, n, col)
	count += 1


## Boîte alignée sur les axes : p = coin minimum, s = dimensions.
func box(p: Vector3, s: Vector3, col: Color) -> void:
	var x0 := p.x
	var x1 := p.x + s.x
	var y0 := p.y
	var y1 := p.y + s.y
	var z0 := p.z
	var z1 := p.z + s.z
	_face(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col)
	_face(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, col)
	_face(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.RIGHT, col)
	_face(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.LEFT, col)
	_face(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, col)
	_face(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, col)


## Prisme vertical (pieds, pots, tabourets…) : centre de la base, rayon, hauteur.
func prism(base: Vector3, r: float, h: float, col: Color, sides: int = 8) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := base + Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am), 0.0, sin(am))
		_face(p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), n, col)
		_tri(base + Vector3(0, h, 0), p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), Vector3.UP, col)


func build(mat: Material, layers: int = 1) -> MeshInstance3D:
	if count == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.layers = layers
	return mi
