extends CanvasLayer
## All HUD, menus, touch controls and screen effects.

signal start_pressed
signal retry_pressed
signal resume_pressed
signal restart_pressed
signal pause_pressed
signal interact_pressed
signal sprint_changed(pressed: bool)
signal move_changed(value: Vector2)

const VirtualJoystickScript := preload("res://scripts/virtual_joystick.gd")
const OVERLAY_SHADER := preload("res://assets/shaders/overlay.gdshader")

const BONE := Color(0.87, 0.85, 0.78)
const GOLD := Color(1.0, 0.78, 0.38)
const BLOOD := Color(0.78, 0.12, 0.1)
const MUTED := Color(0.58, 0.6, 0.56)
const GREEN := Color(0.55, 0.9, 0.6)

var root: Control
var gameplay: Control
var menu: Control
var pause_menu: Control
var end_screen: Control
var jumpscare: TextureRect
var fade_rect: ColorRect
var flash_rect: ColorRect

var book_count: Label
var book_bar: ProgressBar
var stamina_bar: ProgressBar
var stamina_fill: StyleBoxFlat
var stamina_label: Label
var prompt_label: Label
var hint_label: Label
var message_label: Label
var interact_button: Button
var sprint_button: Button
var pause_button: Button
var joystick

var danger_rect: ColorRect
var danger_material: ShaderMaterial
var _danger_target := 0.0
var _danger_shown := 0.0

var _msg_tween: Tween
var _hint_tween: Tween
var _fade_tween: Tween
var _scare_tween: Tween
var _scare_shake: Tween
var _prompt_on := false
var _menu_title: Label

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_full_rect(root)
	_build_gameplay()
	_build_jumpscare()
	_build_menu()
	_build_pause()
	_build_end()
	_build_fade()
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	show_menu()

func _process(delta: float) -> void:
	_danger_shown = lerpf(_danger_shown, _danger_target, 1.0 - exp(-delta * 4.0))
	if danger_material:
		danger_material.set_shader_parameter("danger", _danger_shown)

# ---------------------------------------------------------------------------
# construction helpers
# ---------------------------------------------------------------------------
func _full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _label(text: String, font_size: int, color: Color, outline: int = 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _banner(parent: Control, text: String, top: float, height: float, font_size: int,
		color: Color, outline: int = 8) -> Label:
	var l := _label(text, font_size, color, outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = top + height
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _style(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s

func _button(text: String, font_size: int, radius: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", GOLD)
	var normal := _style(Color(0.07, 0.075, 0.07, 0.78), Color(0.4, 0.4, 0.35, 0.6), radius)
	var hover := _style(Color(0.13, 0.13, 0.11, 0.9), Color(0.8, 0.7, 0.45, 0.8), radius)
	var pressed := _style(Color(0.2, 0.08, 0.06, 0.95), Color(0.9, 0.3, 0.2, 0.9), radius)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	return b

func _progress(width: float, height: float, fill: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, height)
	p.size = Vector2(width, height)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := _style(Color(0.02, 0.025, 0.025, 0.8), Color(0.35, 0.35, 0.3, 0.5), 4)
	bg.set_border_width_all(1)
	var fill_style := _style(fill, fill.lightened(0.2), 4)
	fill_style.set_border_width_all(0)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fill_style)
	return p

# ---------------------------------------------------------------------------
# gameplay HUD
# ---------------------------------------------------------------------------
func _build_gameplay() -> void:
	gameplay = Control.new()
	gameplay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gameplay)
	_full_rect(gameplay)

	danger_rect = ColorRect.new()
	_full_rect(danger_rect)
	danger_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_rect.color = Color.WHITE
	danger_material = ShaderMaterial.new()
	danger_material.shader = OVERLAY_SHADER
	danger_rect.material = danger_material
	gameplay.add_child(danger_rect)

	var objective := VBoxContainer.new()
	objective.position = Vector2(30, 20)
	objective.add_theme_constant_override("separation", 1)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay.add_child(objective)
	var title := _label("BOOKS FOUND", 15, MUTED, 4)
	title.add_theme_color_override("font_color", Color(0.65, 0.65, 0.58))
	objective.add_child(title)
	book_count = _label("00 / 25", 38, GOLD, 8)
	objective.add_child(book_count)
	book_bar = _progress(270, 8, GOLD)
	objective.add_child(book_bar)
	book_bar.max_value = 25

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.32)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -2
	cross.offset_top = -2
	cross.offset_right = 2
	cross.offset_bottom = 2
	gameplay.add_child(cross)

	hint_label = _banner(gameplay, "", 76, 60, 17, Color(0.82, 0.82, 0.74), 6)
	hint_label.modulate.a = 0.0

	message_label = _banner(gameplay, "", 150, 90, 34, BONE, 10)
	message_label.modulate.a = 0.0

	prompt_label = _banner(gameplay, "", 0, 52, 20, Color(0.9, 0.88, 0.8), 7)
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.modulate.a = 0.0

	stamina_label = _label("STAMINA", 13, MUTED, 4)
	gameplay.add_child(stamina_label)
	stamina_bar = _progress(210, 12, GREEN)
	gameplay.add_child(stamina_bar)
	stamina_fill = stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat

	joystick = VirtualJoystickScript.new()
	gameplay.add_child(joystick)
	joystick.vector_changed.connect(func(v: Vector2) -> void: move_changed.emit(v))

	sprint_button = _button("RUN", 22, 999)
	sprint_button.keep_pressed_outside = true
	gameplay.add_child(sprint_button)
	sprint_button.button_down.connect(func() -> void: sprint_changed.emit(true))
	sprint_button.button_up.connect(func() -> void: sprint_changed.emit(false))

	interact_button = _button("TAKE", 18, 26)
	interact_button.visible = false
	gameplay.add_child(interact_button)
	interact_button.pressed.connect(func() -> void: interact_pressed.emit())

	pause_button = _button("II", 18, 12)
	gameplay.add_child(pause_button)
	pause_button.pressed.connect(func() -> void: pause_pressed.emit())

func _on_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	var j := clampf(minf(vp.x, vp.y) * 0.30, 150.0, 232.0)
	joystick.size = Vector2(j, j)
	joystick.position = Vector2(24, vp.y - j - 24)
	stamina_label.position = Vector2(32, joystick.position.y - 44)
	stamina_bar.position = Vector2(30, joystick.position.y - 22)
	var s := clampf(j * 0.72, 104.0, 162.0)
	sprint_button.size = Vector2(s, s)
	sprint_button.position = Vector2(vp.x - s - 30, vp.y - s - 30)
	var ib := s * 0.82
	interact_button.size = Vector2(ib, ib)
	interact_button.position = Vector2(vp.x - ib - 30, sprint_button.position.y - ib - 16)
	pause_button.size = Vector2(48, 48)
	pause_button.position = Vector2(vp.x - 74, 22)
	prompt_label.offset_left = -minf(vp.x * 0.45, 520.0)
	prompt_label.offset_right = minf(vp.x * 0.45, 520.0)
	prompt_label.offset_top = -210
	prompt_label.offset_bottom = -158
	if jumpscare:
		jumpscare.pivot_offset = vp * 0.5
	_update_font_scale(vp)

func _update_font_scale(vp: Vector2) -> void:
	var k := clampf(minf(vp.x / 1280.0, vp.y / 720.0), 0.7, 1.35)
	book_count.add_theme_font_size_override("font_size", int(38 * k))
	message_label.add_theme_font_size_override("font_size", int(34 * k))

# ---------------------------------------------------------------------------
# menus
# ---------------------------------------------------------------------------
func _build_menu() -> void:
	menu = Control.new()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu)
	_full_rect(menu)

	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.009, 0.012, 0.98)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bg)
	_full_rect(bg)

	var face := TextureRect.new()
	face.texture = load("res://HANTU.jpeg")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.modulate = Color(1.0, 1.0, 1.0, 0.17)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(face)
	_full_rect(face)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)
	_full_rect(shade)

	var ghost_title := _banner(menu, "HANTU", 54, 160, 124, Color(0.42, 0.05, 0.04, 0.9), 18)
	ghost_title.position.x = 4
	ghost_title.position.y = 7
	_menu_title = _banner(menu, "HANTU", 54, 160, 124, BONE, 16)
	var sub := _banner(menu, "T H E   2 5   B O O K S", 214, 40, 24, Color(0.76, 0.7, 0.58), 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))

	var line := ColorRect.new()
	line.color = Color(0.55, 0.5, 0.38, 0.45)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	line.offset_left = -210
	line.offset_right = 210
	line.offset_top = 270
	line.offset_bottom = 272
	menu.add_child(line)

	var desc := _banner(menu,
		"Twenty-five books are scattered through the house.\nFind every one, and the front door will open.\n\nIt only hunts what it can see.",
		298, 120, 18, Color(0.74, 0.75, 0.68), 5)
	desc.add_theme_color_override("font_color", MUTED)

	var start := _button("ENTER THE HOUSE", 24, 8)
	start.set_anchors_preset(Control.PRESET_CENTER_TOP)
	start.offset_left = -190
	start.offset_right = 190
	start.offset_top = 444
	start.offset_bottom = 510
	menu.add_child(start)
	start.pressed.connect(func() -> void:
		Sfx.play_sfx("click", -6.0)
		start_pressed.emit()
	)

	var hint := _banner(menu, _controls_text(), 548, 70, 15, Color(0.55, 0.57, 0.52), 4)
	hint.add_theme_color_override("font_color", Color(0.55, 0.57, 0.52))

	var quit := _button("QUIT", 15, 8)
	quit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quit.offset_left = -146
	quit.offset_right = -24
	quit.offset_top = -84
	quit.offset_bottom = -44
	menu.add_child(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())

	var warn := _banner(menu, "HEADPHONES RECOMMENDED  ·  FLASHING LIGHTS  ·  DO NOT LET IT SEE YOU",
		0, 30, 12, Color(0.42, 0.44, 0.4), 4)
	warn.anchor_top = 1.0
	warn.anchor_bottom = 1.0
	warn.offset_top = -24
	warn.offset_bottom = 6

	var title_tween := create_tween().set_loops()
	title_tween.tween_property(_menu_title, "modulate", Color(0.92, 0.9, 0.82), 2.4)
	title_tween.tween_property(_menu_title, "modulate", Color(0.72, 0.68, 0.6), 2.8)

func _controls_text() -> String:
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		return "LEFT STICK — MOVE      SWIPE RIGHT — LOOK\nHOLD RUN — SPRINT      TAKE — PICK UP BOOKS"
	return "WASD — MOVE      MOUSE — LOOK      SHIFT — SPRINT\nE — TAKE      ESC — PAUSE"

func _build_pause() -> void:
	pause_menu = Control.new()
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pause_menu)
	_full_rect(pause_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.005, 0.006, 0.008, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu.add_child(bg)
	_full_rect(bg)
	_banner(pause_menu, "PAUSED", 168, 90, 66, BONE, 12)
	_banner(pause_menu, "The house is holding its breath.", 250, 40, 18, MUTED, 4)

	var resume := _button("RESUME", 22, 8)
	resume.set_anchors_preset(Control.PRESET_CENTER_TOP)
	resume.offset_left = -150
	resume.offset_right = 150
	resume.offset_top = 330
	resume.offset_bottom = 390
	pause_menu.add_child(resume)
	resume.pressed.connect(func() -> void: resume_pressed.emit())

	var restart := _button("RESTART", 22, 8)
	restart.set_anchors_preset(Control.PRESET_CENTER_TOP)
	restart.offset_left = -150
	restart.offset_right = 150
	restart.offset_top = 406
	restart.offset_bottom = 466
	pause_menu.add_child(restart)
	restart.pressed.connect(func() -> void: restart_pressed.emit())

	var esc := _banner(pause_menu, "ESC TO RESUME", 0, 30, 13, Color(0.45, 0.46, 0.42), 4)
	esc.anchor_top = 1.0
	esc.anchor_bottom = 1.0
	esc.offset_top = -42
	esc.offset_bottom = -12
	pause_menu.visible = false

func _build_end() -> void:
	end_screen = Control.new()
	end_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(end_screen)
	_full_rect(end_screen)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.005, 0.005, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_screen.add_child(bg)
	_full_rect(bg)

	var title := _banner(end_screen, "DITANGKAP", 150, 120, 92, BLOOD, 14)
	title.name = "Title"
	var sub := _banner(end_screen, "It found you.", 272, 40, 21, MUTED, 5)
	sub.name = "Sub"
	var stats := _banner(end_screen, "", 330, 40, 18, Color(0.7, 0.68, 0.6), 4)
	stats.name = "Stats"

	var retry := _button("TRY AGAIN", 24, 8)
	retry.name = "Retry"
	retry.set_anchors_preset(Control.PRESET_CENTER_TOP)
	retry.offset_left = -175
	retry.offset_right = 175
	retry.offset_top = 420
	retry.offset_bottom = 486
	end_screen.add_child(retry)
	retry.pressed.connect(func() -> void: retry_pressed.emit())
	end_screen.visible = false

func _build_jumpscare() -> void:
	jumpscare = TextureRect.new()
	jumpscare.texture = load("res://HANTU.jpeg")
	jumpscare.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	jumpscare.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	jumpscare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jumpscare.visible = false
	root.add_child(jumpscare)
	_full_rect(jumpscare)

func _build_fade() -> void:
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.6, 0.02, 0.0, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	_full_rect(flash_rect)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)
	_full_rect(fade_rect)

# ---------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------
func set_books(found: int, total: int) -> void:
	book_count.text = "%02d / %d" % [found, total]
	book_bar.max_value = total
	book_bar.value = found
	if found > 0:
		var t := create_tween()
		book_count.pivot_offset = book_count.size * 0.5
		book_count.scale = Vector2(1.25, 1.25)
		t.tween_property(book_count, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)

func set_stamina(value: float) -> void:
	stamina_bar.value = value
	if stamina_fill:
		if value > 55.0:
			stamina_fill.bg_color = GREEN
		elif value > 22.0:
			stamina_fill.bg_color = Color(0.9, 0.72, 0.28)
		else:
			stamina_fill.bg_color = Color(0.85, 0.18, 0.12)

func set_danger(value: float) -> void:
	_danger_target = clampf(value, 0.0, 1.0)

func show_prompt(text: String) -> void:
	if _prompt_on and prompt_label.text == text:
		return
	_prompt_on = true
	prompt_label.text = text
	var t := create_tween()
	t.tween_property(prompt_label, "modulate:a", 1.0, 0.15)

func hide_prompt() -> void:
	if not _prompt_on:
		return
	_prompt_on = false
	var t := create_tween()
	t.tween_property(prompt_label, "modulate:a", 0.0, 0.2)

func set_interact_visible(visible: bool, label: String = "TAKE") -> void:
	interact_button.text = label
	interact_button.visible = visible

func flash_message(text: String, color: Color = BONE, duration: float = 2.6) -> void:
	if _msg_tween and _msg_tween.is_valid():
		_msg_tween.kill()
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.modulate.a = 0.0
	message_label.scale = Vector2(0.94, 0.94)
	message_label.pivot_offset = message_label.size * 0.5
	_msg_tween = create_tween()
	_msg_tween.set_parallel()
	_msg_tween.tween_property(message_label, "modulate:a", 1.0, 0.22)
	_msg_tween.tween_property(message_label, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK)
	_msg_tween.set_parallel(false)
	_msg_tween.tween_interval(duration)
	_msg_tween.tween_property(message_label, "modulate:a", 0.0, 0.6)

func show_hint(text: String, duration: float = 9.0) -> void:
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	hint_label.text = text
	hint_label.modulate.a = 0.0
	_hint_tween = create_tween()
	_hint_tween.tween_property(hint_label, "modulate:a", 1.0, 0.5)
	_hint_tween.tween_interval(duration)
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 1.0)

func show_menu() -> void:
	gameplay.visible = false
	menu.visible = true
	pause_menu.visible = false
	end_screen.visible = false
	jumpscare.visible = false
	fade_rect.color.a = 0.0

func show_gameplay() -> void:
	gameplay.visible = true
	menu.visible = false
	pause_menu.visible = false
	end_screen.visible = false

func show_pause(paused: bool) -> void:
	pause_menu.visible = paused

func show_end(won: bool, seconds: float, books: int) -> void:
	pause_menu.visible = false
	end_screen.visible = true
	var title := end_screen.get_node("Title") as Label
	var sub := end_screen.get_node("Sub") as Label
	var stats := end_screen.get_node("Stats") as Label
	var retry := end_screen.get_node("Retry") as Button
	if won:
		title.text = "YOU ESCAPED"
		title.add_theme_color_override("font_color", Color(0.8, 0.88, 0.62))
		sub.text = "The house lets you leave. This time."
		retry.text = "PLAY AGAIN"
	else:
		title.text = "DITANGKAP"
		title.add_theme_color_override("font_color", BLOOD)
		sub.text = "It found you. The books stay."
		retry.text = "TRY AGAIN"
	stats.text = "BOOKS  %d / 25        TIME  %s" % [books, _format_time(seconds)]
	fade_rect.color.a = 0.0

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [floori(s / 60.0), s % 60]

func show_jumpscare() -> void:
	jumpscare.visible = true
	flash_rect.color = Color(0.55, 0.0, 0.0, 0.0)
	jumpscare.modulate = Color.WHITE
	jumpscare.scale = Vector2(1.55, 1.55)
	jumpscare.rotation = 0.0
	jumpscare.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	if _scare_tween and _scare_tween.is_valid():
		_scare_tween.kill()
	if _scare_shake and _scare_shake.is_valid():
		_scare_shake.kill()
	_scare_tween = create_tween()
	_scare_tween.set_parallel()
	_scare_tween.tween_property(jumpscare, "scale", Vector2(1.04, 1.04), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_scare_tween.tween_property(flash_rect, "color:a", 0.35, 0.06)
	_scare_tween.tween_property(flash_rect, "color:a", 0.0, 0.5).set_delay(0.1)
	_scare_shake = create_tween().set_loops(14)
	_scare_shake.tween_property(jumpscare, "rotation", 0.022, 0.035)
	_scare_shake.tween_property(jumpscare, "rotation", -0.022, 0.035)
	_scare_shake.tween_property(jumpscare, "position", Vector2(14, -8), 0.03)
	_scare_shake.tween_property(jumpscare, "position", Vector2(-12, 10), 0.03)
	_scare_shake.tween_property(jumpscare, "position", Vector2.ZERO, 0.03)

func hide_jumpscare() -> void:
	if _scare_shake and _scare_shake.is_valid():
		_scare_shake.kill()
	jumpscare.visible = false
	jumpscare.position = Vector2.ZERO
	jumpscare.rotation = 0.0

func fade_out(duration: float = 0.35) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 1.0, duration)

func fade_in(duration: float = 0.6) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 0.0, duration)
