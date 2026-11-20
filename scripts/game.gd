extends Node3D
## Prototype : une pièce 3D, un personnage provisoire (capsule), joystick tactile, caméra 3e personne.
## Tout est construit par code (aucun asset externe) pour garder le téléchargement minuscule.

const ROOM_W := 8.0
const ROOM_D := 6.0
const WALL_H := 2.8
const SPEED := 3.6
const GRAVITY := 20.0
const JOY_RADIUS := 90.0

var player: CharacterBody3D
var body_pivot: Node3D
var cam: Camera3D
var yaw := 0.0
var pitch := 0.45
var cam_dist := 4.0

var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_id := -1

var joy_draw: Control
var rotate_hint: Control
var _log_timer := 0.0


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_player()
	_build_hud()
	print("[PTA] jeu démarré")


# ---------------------------------------------------------------- décor

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("3b1560")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffb3d9")
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffb070")
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ff7ab8")
	lamp.omni_range = 8.0
	lamp.light_energy = 1.0
	lamp.position = Vector3(0, 2.4, 0)
	add_child(lamp)


func _mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if emissive:
		m.emission_enabled = true
		m.emission = color
	return m


func _box(pos: Vector3, size: Vector3, color: Color, solid: bool = true, emissive: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, emissive)
	mi.position = pos
	add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.position = pos
		sb.add_child(cs)
		add_child(sb)


func _build_room() -> void:
	var hw := ROOM_W * 0.5
	var hd := ROOM_D * 0.5
	# sol + tapis
	_box(Vector3(0, -0.1, 0), Vector3(ROOM_W + 0.4, 0.2, ROOM_D + 0.4), Color("8a4fd0"))
	_box(Vector3(0, 0.01, 0.4), Vector3(3.2, 0.02, 2.2), Color("ff5fa2"), false)
	# murs
	_box(Vector3(0, WALL_H * 0.5, -hd - 0.1), Vector3(ROOM_W + 0.4, WALL_H, 0.2), Color("e0559a"))
	_box(Vector3(0, WALL_H * 0.5, hd + 0.1), Vector3(ROOM_W + 0.4, WALL_H, 0.2), Color("ff9a52"))
	_box(Vector3(-hw - 0.1, WALL_H * 0.5, 0), Vector3(0.2, WALL_H, ROOM_D), Color("b04bd0"))
	_box(Vector3(hw + 0.1, WALL_H * 0.5, 0), Vector3(0.2, WALL_H, ROOM_D), Color("b04bd0"))
	# fenêtre « coucher de soleil »
	_box(Vector3(1.5, 1.6, -hd + 0.02), Vector3(1.6, 1.0, 0.04), Color("ffb347"), false, true)
	# quelques meubles pour donner l'échelle
	_box(Vector3(-2.6, 0.4, -2.3), Vector3(1.4, 0.8, 0.8), Color("ffc14d"))
	_box(Vector3(2.5, 0.35, 2.0), Vector3(1.8, 0.7, 0.9), Color("4fd1c5"))
	_box(Vector3(-3.3, 0.5, 1.4), Vector3(0.6, 1.0, 0.6), Color("5a2d91"))


# ---------------------------------------------------------------- joueur

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0.05, 1.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	player.add_child(cs)

	body_pivot = Node3D.new()
	player.add_child(body_pivot)

	var mesh := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.7
	cm.radial_segments = 16
	cm.rings = 6
	mesh.mesh = cm
	mesh.material_override = _mat(Color("ff7a3d"))
	mesh.position.y = 0.85
	body_pivot.add_child(mesh)

	# petit « nez » pour voir l'orientation (l'avant est -Z)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.18, 0.12, 0.2)
	nose.mesh = nm
	nose.material_override = _mat(Color.WHITE)
	nose.position = Vector3(0, 1.4, -0.3)
	body_pivot.add_child(nose)

	add_child(player)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	_update_camera()


# ---------------------------------------------------------------- interface

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	joy_draw = Control.new()
	joy_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_draw.draw.connect(_on_joy_draw)
	layer.add_child(joy_draw)

	var help := Label.new()
	help.text = "Joystick à gauche · glisse à droite pour tourner la caméra"
	help.position = Vector2(16, 12)
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_color", Color.WHITE)
	help.add_theme_color_override("font_outline_color", Color("2a0f4d"))
	help.add_theme_constant_override("outline_size", 6)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help)
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(help, "modulate:a", 0.0, 1.5)

	# invitation à passer en paysage si l'écran est en portrait
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.03, 0.2, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var msg := Label.new()
	msg.text = "Tourne ton téléphone\nen mode paysage"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 40)
	msg.add_theme_color_override("font_color", Color.WHITE)
	shade.add_child(msg)
	layer.add_child(shade)
	rotate_hint = shade


func _on_joy_draw() -> void:
	var size := get_viewport().get_visible_rect().size
	if joy_id == -1:
		joy_draw.draw_arc(Vector2(130, size.y - 120), JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 3.0)
		return
	joy_draw.draw_circle(joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
	joy_draw.draw_arc(joy_origin, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.4), 3.0)
	var knob := joy_pos - joy_origin
	if knob.length() > JOY_RADIUS:
		knob = knob.normalized() * JOY_RADIUS
	joy_draw.draw_circle(joy_origin + knob, 38.0, Color(1, 1, 1, 0.5))


# ---------------------------------------------------------------- entrées

func _input(event: InputEvent) -> void:
	var w := get_viewport().get_visible_rect().size.x
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventScreenDrag
	if touch != null:
		if touch.pressed:
			if touch.position.x < w * 0.5:
				if joy_id == -1:
					joy_id = touch.index
					joy_origin = touch.position
					joy_pos = touch.position
			elif look_id == -1:
				look_id = touch.index
		else:
			if touch.index == joy_id:
				joy_id = -1
			if touch.index == look_id:
				look_id = -1
		joy_draw.queue_redraw()
	elif drag != null:
		if drag.index == joy_id:
			joy_pos = drag.position
			joy_draw.queue_redraw()
		elif drag.index == look_id:
			yaw -= drag.relative.x * 0.006
			pitch = clampf(pitch + drag.relative.y * 0.004, 0.15, 1.0)


func _move_input() -> Vector2:
	var v := Vector2.ZERO
	if joy_id != -1:
		v = (joy_pos - joy_origin) / JOY_RADIUS
	var kx := 0.0
	var ky := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		kx -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kx += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
		ky -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		ky += 1.0
	v += Vector2(kx, ky)
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < 0.12:
		v = Vector2.ZERO
	return v


# ---------------------------------------------------------------- boucle

func _physics_process(delta: float) -> void:
	var v := _move_input()
	var dir := Vector3(v.x, 0.0, v.y).rotated(Vector3.UP, yaw)
	var vel := player.velocity
	vel.x = dir.x * SPEED
	vel.z = dir.z * SPEED
	if player.is_on_floor():
		vel.y = 0.0
	else:
		vel.y -= GRAVITY * delta
	player.velocity = vel
	player.move_and_slide()
	if v != Vector2.ZERO:
		body_pivot.rotation.y = lerp_angle(body_pivot.rotation.y, atan2(-dir.x, -dir.z), clampf(12.0 * delta, 0.0, 1.0))
		_log_timer += delta
		if _log_timer >= 1.0:
			_log_timer = 0.0
			print("[PTA] pos ", snappedf(player.position.x, 0.01), " ", snappedf(player.position.z, 0.01))


func _process(_delta: float) -> void:
	var s := get_viewport().get_visible_rect().size
	rotate_hint.visible = s.x < s.y
	_update_camera()


func _update_camera() -> void:
	var target := player.global_position + Vector3(0, 1.2, 0)
	var off := (Vector3(0, sin(pitch), cos(pitch)) * cam_dist).rotated(Vector3.UP, yaw)
	var p := target + off
	var mx := ROOM_W * 0.5 - 0.25
	var mz := ROOM_D * 0.5 - 0.25
	p.x = clampf(p.x, -mx, mx)
	p.z = clampf(p.z, -mz, mz)
	p.y = clampf(p.y, 0.4, WALL_H - 0.15)
	cam.global_position = p
	cam.look_at(target)
