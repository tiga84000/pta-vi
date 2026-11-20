extends Node
## Point d'entrée : écran d'accueil, puis lancement du jeu.
## Le clic sur « JOUER » sert aussi de geste utilisateur pour débloquer l'audio sur Safari iOS.

const GameScript := preload("res://scripts/game.gd")


func _ready() -> void:
	# modes de test (?autotest=1, ?spawn=...) : on passe directement au jeu
	if GameScript.has_flag("autotest") or GameScript.param("spawn", "") != "":
		add_child(GameScript.new())
		return
	_show_title()


func _show_title() -> void:
	var ui := Control.new()
	ui.name = "Title"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color("2a0f4d"), Color("c2307a"), Color("ff8a3d")])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	ui.add_child(box)

	box.add_child(_label("PTA VI", 110, Color.WHITE))
	box.add_child(_label("P’TITE TEUB AUTO", 36, Color("ffd9a8")))
	box.add_child(_label("V0.2", 20, Color("ffffff")))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)

	var btn := Button.new()
	btn.text = "JOUER"
	btn.custom_minimum_size = Vector2(300, 84)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 44)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style(Color("ff3d8b")))
	btn.add_theme_stylebox_override("hover", _style(Color("ff5aa0")))
	btn.add_theme_stylebox_override("pressed", _style(Color("c2307a")))
	btn.pressed.connect(_start.bind(ui))
	box.add_child(btn)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("2a0f4d"))
	l.add_theme_constant_override("outline_size", 12)
	return l


func _style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(18)
	s.set_border_width_all(4)
	s.border_color = Color("ffd9a8")
	return s


func _start(ui: Control) -> void:
	ui.queue_free()
	add_child(GameScript.new())
