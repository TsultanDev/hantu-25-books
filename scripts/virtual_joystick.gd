extends Control
## A round on-screen thumbstick. Emits a normalized vector (screen space).

signal vector_changed(value: Vector2)

var value := Vector2.ZERO

var _touch_index := -1
var _mouse_active := false
var _radius := 60.0
var _knob_radius := 22.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_radius = minf(size.x, size.y) * 0.32
	_knob_radius = minf(size.x, size.y) * 0.155
	queue_redraw()

func _inside(local_pos: Vector2) -> bool:
	return local_pos.distance_to(size * 0.5) <= _radius * 1.45

func _set_from_local(local_pos: Vector2) -> void:
	var offset := local_pos - size * 0.5
	var v := offset / maxf(_radius, 1.0)
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < 0.12:
		v = Vector2.ZERO
	value = v
	vector_changed.emit(value)
	queue_redraw()

func _release() -> void:
	value = Vector2.ZERO
	vector_changed.emit(value)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and _inside(event.position):
			_touch_index = event.index
			_set_from_local(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_set_from_local(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _inside(event.position):
			_mouse_active = true
			_set_from_local(event.position)
			accept_event()
		elif not event.pressed and _mouse_active:
			_mouse_active = false
			_release()
			accept_event()
	elif event is InputEventMouseMotion and _mouse_active:
		_set_from_local(event.position)
		accept_event()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, _radius * 1.2, Color(0.02, 0.025, 0.025, 0.28))
	draw_circle(center, _radius, Color(0.06, 0.07, 0.07, 0.55))
	draw_arc(center, _radius, 0.0, TAU, 64, Color(0.62, 0.64, 0.6, 0.35), 2.0, true)
	draw_arc(center, _radius * 0.62, 0.0, TAU, 48, Color(0.4, 0.42, 0.4, 0.18), 1.0, true)
	var knob_pos := center + value * _radius
	draw_circle(knob_pos, _knob_radius * 1.25, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(knob_pos, _knob_radius, Color(0.66, 0.68, 0.63, 0.8))
	draw_arc(knob_pos, _knob_radius, 0.0, TAU, 40, Color(0.9, 0.9, 0.84, 0.35), 1.5, true)
