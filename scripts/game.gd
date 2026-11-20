extends Node3D
## V0.2 : l'appartement de Yannick. Joueur provisoire (capsule), joystick tactile, caméra 3e personne
## avec collisions (SpringArm3D). Les commandes tactiles et le clavier sont ceux de la V0.1.
##
## Paramètres d'URL (tests uniquement) : ?autotest=1 · ?spawn=chambre|hall|sdb|salon|kitchen|verriere · ?yaw=<degrés>

const JOY_RADIUS := 90.0
const SPEED := 3.4
const GRAVITY := 20.0
const CAM_DIST := 2.6

static var _query := ""
static var _query_read := false

var apt: Apartment
var player: CharacterBody3D
var body_pivot: Node3D
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var yaw := 0.0
var pitch := 0.5

var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_id := -1
var joy_draw: Control
var rotate_hint: Control
var _log_timer := 0.0

# --- autotest ---
var autotest := false
var done := false
var wps: Array = []
var wp_i := 0
var wp_t := 0.0
var tstep := 0.0
var reached: Array = []
var fails: Array = []
var viol_pos := 0
var viol_cam := 0
var min_arm := 99.0
var max_dc := 0
var max_prim := 0
var max_obj := 0
var tex_mem := 0
var fps_sum := 0.0
var fps_n := 0
var frame_n := 0


static func query() -> String:
	if not _query_read:
		_query_read = true
		if OS.has_feature("web"):
			_query = str(JavaScriptBridge.eval("window.location.search"))
		else:
			# hors navigateur (tests en ligne de commande) : godot ... -- --autotest=1 --quitdone=1
			var parts := PackedStringArray()
			for a in OS.get_cmdline_user_args():
				parts.append(String(a).trim_prefix("--"))
			_query = "?" + "&".join(parts)
	return _query


static func has_flag(flag: String) -> bool:
	return query().contains(flag)


static func param(key: String, default_value: String) -> String:
	for part in query().trim_prefix("?").split("&"):
		var kv := String(part).split("=")
		if kv.size() == 2 and kv[0] == key:
			return kv[1]
	return default_value


func _ready() -> void:
	apt = Apartment.new()
	add_child(apt)
	apt.build()
	_build_player()
	_build_hud()
	autotest = has_flag("autotest")
	var spawn_name := param("spawn", "chambre")
	if apt.spawns.has(spawn_name):
		var s: Array = apt.spawns[spawn_name]
		player.position = s[0]
		yaw = float(s[1])
		body_pivot.rotation.y = yaw
	if param("yaw", "") != "":
		yaw = deg_to_rad(float(param("yaw", "0")))
	if param("pitch", "") != "":
		pitch = deg_to_rad(float(param("pitch", "0")))
	if autotest:
		_setup_autotest()
	print("[PTA] jeu démarré (V0.2)")


# ---------------------------------------------------------------- joueur + caméra

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = 4
	player.collision_mask = 3
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
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("d8742f")
	m.roughness = 0.8
	mesh.material_override = m
	mesh.position.y = 0.85
	body_pivot.add_child(mesh)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.18, 0.12, 0.2)
	nose.mesh = nm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("f0eee8")
	nose.material_override = wm
	nose.position = Vector3(0, 1.4, -0.3)
	body_pivot.add_child(nose)
	player.position = Vector3(1.6, 0.05, 1.6)
	add_child(player)

	pivot = Node3D.new()
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = CAM_DIST
	arm.collision_mask = 1
	arm.margin = 0.12
	var ss := SphereShape3D.new()
	ss.radius = 0.22
	arm.shape = ss
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	arm.add_child(cam)
	cam.current = true
	_update_camera()


func _update_camera() -> void:
	pivot.global_position = player.global_position + Vector3(0, 1.5, 0)
	pivot.rotation = Vector3(-pitch, yaw, 0.0)
	# le joueur disparaît si la caméra est collée à lui (évite de voir l'intérieur de la capsule)
	var dist := cam.global_position.distance_to(pivot.global_position)
	body_pivot.visible = dist > 0.85
	var lit := 3 if apt.is_open_space(player.position) else 1
	for c in body_pivot.get_children():
		(c as MeshInstance3D).layers = lit


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
	help.add_theme_color_override("font_outline_color", Color("1a1a24"))
	help.add_theme_constant_override("outline_size", 6)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help)
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(help, "modulate:a", 0.0, 1.5)

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


# ---------------------------------------------------------------- entrées (identiques à la V0.1)

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
			pitch = clampf(pitch + drag.relative.y * 0.004, -0.8, 1.1)


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
	if autotest and not done:
		var a := _auto_dir(delta)
		v = a
		dir = Vector3(a.x, 0.0, a.y)   # direction monde : la caméra peut tourner librement pendant le test
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
	# la caméra est mise à jour dans le tick physique (avant le SpringArm3D enfant) : pivot, yaw et
	# collision du bras restent cohérents même quand le rendu est plus lent que la physique
	_update_camera()
	if autotest and not done:
		_check_player()


func _process(_delta: float) -> void:
	var s := get_viewport().get_visible_rect().size
	rotate_hint.visible = s.x < s.y
	if autotest and not done:
		_check_camera()


# ---------------------------------------------------------------- autotest embarqué

func _setup_autotest() -> void:
	wps = [
		["chambre_porte", 1.55, 2.6], ["hall", 1.55, 3.6], ["hall_est", 2.0, 4.35], ["passage_salon", 3.2, 4.35],
		["salon_ouest", 4.2, 3.9], ["sdb_porte", 4.65, 2.75], ["sdb", 4.85, 1.35], ["sdb_sortie", 4.65, 2.75],
		["couloir_salon", 5.0, 2.86], ["salon_est", 6.9, 2.86], ["cuisine", 6.85, 1.2], ["salon_est_retour", 6.9, 2.86],
		["sous_verriere", 6.3, 2.95], ["salon_nord_ouest", 4.5, 2.95], ["derriere_canape", 4.3, 4.3],
	]
	player.position = Vector3(1.6, 0.05, 1.6)
	print("[PTA-TEST] début : %d points de passage" % wps.size())


func _auto_dir(delta: float) -> Vector2:
	tstep += delta
	yaw = tstep * 0.7
	pitch = 0.3 + 0.7 * sin(tstep * 0.9)
	if wp_i >= wps.size():
		_finish_test()
		return Vector2.ZERO
	var w: Array = wps[wp_i]
	var d := Vector2(float(w[1]), float(w[2])) - Vector2(player.position.x, player.position.z)
	wp_t += delta
	if d.length() < 0.3:
		reached.append(w[0])
		print("[PTA-TEST] atteint %s (%.1f s)" % [w[0], wp_t])
		wp_i += 1
		wp_t = 0.0
		return Vector2.ZERO
	if wp_t > 15.0:
		fails.append(w[0])
		print("[PTA-TEST] ECHEC %s pos=%s" % [w[0], player.position])
		wp_i += 1
		wp_t = 0.0
		return Vector2.ZERO
	return d.normalized()


func _check_player() -> void:
	var p := player.position
	var bad := false
	if p.x < 0.1 or p.x > 7.9 or p.z < 0.1 or p.z > 5.4 or p.y < -0.2:
		bad = true
	for s in apt.solids:
		var mn: Vector3 = s["min"]
		var mx: Vector3 = s["max"]
		if mn.y > 1.6 or mx.y < 0.15:
			continue
		if p.x > mn.x + 0.04 and p.x < mx.x - 0.04 and p.z > mn.z + 0.04 and p.z < mx.z - 0.04:
			bad = true
			break
	if bad:
		viol_pos += 1
		if viol_pos < 4:
			print("[PTA-TEST] VIOLATION position %s" % p)


func _check_camera() -> void:
	frame_n += 1
	var cp := cam.global_position
	var bad := false
	for s in apt.solids:
		if not bool(s["cam"]):
			continue
		var mn: Vector3 = s["min"]
		var mx: Vector3 = s["max"]
		if cp.x > mn.x + 0.01 and cp.x < mx.x - 0.01 and cp.y > mn.y + 0.01 and cp.y < mx.y - 0.01 and cp.z > mn.z + 0.01 and cp.z < mx.z - 0.01:
			bad = true
			break
	if bad:
		viol_cam += 1
		if viol_cam < 4:
			print("[PTA-TEST] VIOLATION caméra %s" % cp)
	min_arm = minf(min_arm, arm.get_hit_length())
	if frame_n > 10 and frame_n % 5 == 0:
		max_dc = maxi(max_dc, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		max_prim = maxi(max_prim, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
		max_obj = maxi(max_obj, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)))
		tex_mem = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
		fps_sum += Engine.get_frames_per_second()
		fps_n += 1


func _finish_test() -> void:
	if done:
		return
	done = true
	var ok := fails.is_empty() and viol_pos == 0 and viol_cam == 0 and reached.size() == wps.size()
	var res := {
		"pass": ok, "waypoints": wps.size(), "reached": reached.size(), "fails": fails,
		"viol_pos": viol_pos, "viol_cam": viol_cam, "min_arm": snappedf(min_arm, 0.01),
		"draw_calls_max": max_dc, "primitives_max": max_prim, "objects_max": max_obj,
		"texture_mem_mb": snappedf(float(tex_mem) / 1048576.0, 0.1),
		"fps_avg": snappedf(fps_sum / maxf(float(fps_n), 1.0), 0.1),
	}
	print("[PTA-TEST] RESULT ", JSON.stringify(res))
	if has_flag("quitdone"):
		get_tree().quit()
