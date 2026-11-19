extends CharacterBody3D
## First-person player: movement, stamina, head bob, touch/keyboard look.

signal stamina_changed(value: float)
signal sprinting_changed(active: bool)

const STEP_SOUND := preload("res://assets/audio/step.wav")

@export var walk_speed := 2.9
@export var sprint_speed := 5.5
@export var acceleration := 12.0
@export var max_stamina := 100.0
@export var sprint_drain := 17.0
@export var stamina_regen := 10.5
@export var touch_look_sensitivity := 0.0034
@export var mouse_look_sensitivity := 0.0022

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var flashlight: SpotLight3D = $Head/Flashlight
@onready var footstep_player: AudioStreamPlayer = $Footsteps

var stamina := 100.0
var can_move := false
var sprint_held := false
var sprinting := false
var move_input := Vector2.ZERO

var _pitch := 0.0
var _look_touch := -1
var _gravity := 9.8
var _bob_time := 0.0
var _bob_strength := 0.0
var _foot_distance := 0.0
var _stamina_cooldown := 0.0
var _exhausted := false
var _last_stamina_report := -1.0
var _trauma := 0.0
var _fear := 0.0
var _flicker_time := 0.0
var _flash_base_energy := 5.0

func _ready() -> void:
	footstep_player.stream = STEP_SOUND
	_flash_base_energy = flashlight.light_energy
	stamina = max_stamina
	stamina_changed.emit(stamina)

func set_control(enabled: bool) -> void:
	can_move = enabled
	if not enabled:
		move_input = Vector2.ZERO
		sprint_held = false
		_look_touch = -1

func set_move_input(v: Vector2) -> void:
	move_input = v

func set_sprint_held(pressed: bool) -> void:
	sprint_held = pressed

func add_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, max_stamina)
	_report_stamina(true)

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func set_fear(value: float) -> void:
	_fear = clampf(value, 0.0, 1.0)

func force_look_at(target: Vector3) -> void:
	var d := target - get_global_transform().origin
	rotation.y = atan2(-d.x, -d.z)
	_pitch = clampf(atan2(d.y - 1.4, Vector2(d.x, d.z).length()), -1.2, 1.2)
	head.rotation.x = _pitch

func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_look(event.relative * mouse_look_sensitivity)
	elif event is InputEventScreenTouch:
		var vp := get_viewport().get_visible_rect().size
		if event.pressed and _look_touch == -1 and event.position.x > vp.x * 0.26:
			_look_touch = event.index
		elif not event.pressed and event.index == _look_touch:
			_look_touch = -1
	elif event is InputEventScreenDrag and event.index == _look_touch:
		_rotate_look(event.relative * touch_look_sensitivity)

func _rotate_look(delta_look: Vector2) -> void:
	rotation.y -= delta_look.x
	_pitch = clampf(_pitch - delta_look.y, deg_to_rad(-82.0), deg_to_rad(82.0))
	head.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not can_move:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		sprinting = false
		_update_head(delta, 0.0)
		return

	var input := move_input
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	input = input.limit_length(1.0)

	var wants_sprint := (sprint_held or Input.is_physical_key_pressed(KEY_SHIFT)) and input.length() > 0.15
	if _stamina_cooldown > 0.0:
		_stamina_cooldown -= delta

	var was_sprinting := sprinting
	sprinting = wants_sprint and stamina > 0.5 and not _exhausted
	if sprinting:
		stamina = maxf(0.0, stamina - sprint_drain * delta)
		_stamina_cooldown = 0.85
		if stamina <= 0.01:
			sprinting = false
			_exhausted = true
			_stamina_cooldown = 1.2
	else:
		if _stamina_cooldown <= 0.0:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)
		if _exhausted and stamina >= 30.0:
			_exhausted = false
	if sprinting != was_sprinting:
		sprinting_changed.emit(sprinting)

	var speed := sprint_speed if sprinting else walk_speed
	var target := (transform.basis * Vector3(input.x, 0.0, input.y)) * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.2
	move_and_slide()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_update_head(delta, planar_speed)
	_update_footsteps(delta, planar_speed)
	_report_stamina()

func _update_head(delta: float, planar_speed: float) -> void:
	var target_bob := clampf(planar_speed / walk_speed, 0.0, 1.8)
	_bob_strength = lerpf(_bob_strength, target_bob, 1.0 - exp(-delta * 8.0))
	_bob_time += delta * (2.2 + planar_speed * 1.6)
	var bob_y := sin(_bob_time * 2.0) * 0.035 * _bob_strength
	var bob_x := cos(_bob_time) * 0.022 * _bob_strength
	var breathe := sin(Time.get_ticks_msec() * 0.0012) * 0.006
	head.position = Vector3(bob_x, 1.6 + bob_y + breathe, 0.0)

	_trauma = maxf(0.0, _trauma - delta * 0.85)
	var shake := _trauma * _trauma
	camera.position = Vector3(
		randf_range(-1.0, 1.0) * 0.13 * shake,
		randf_range(-1.0, 1.0) * 0.11 * shake,
		0.0
	)
	camera.rotation.z = randf_range(-1.0, 1.0) * 0.07 * shake
	var target_fov := 84.0 if sprinting else 78.0
	camera.fov = lerpf(camera.fov, target_fov - _fear * 2.0, 1.0 - exp(-delta * 6.0))

	# The torch gets nervous around the ghost.
	_flicker_time += delta
	var flicker := 1.0
	if _fear > 0.03:
		flicker -= _fear * 0.22 * (0.5 + 0.5 * sin(_flicker_time * 43.0))
		flicker -= _fear * 0.12 * randf()
	flicker += sin(_flicker_time * 3.1) * 0.012
	flashlight.light_energy = _flash_base_energy * clampf(flicker, 0.25, 1.1)

func _update_footsteps(delta: float, planar_speed: float) -> void:
	if not is_on_floor() or planar_speed < 0.4:
		return
	_foot_distance += planar_speed * delta
	if _foot_distance >= 2.25:
		_foot_distance = 0.0
		footstep_player.pitch_scale = randf_range(0.82, 1.18)
		footstep_player.volume_db = -8.0 if sprinting else -14.0
		footstep_player.play()

func _report_stamina(force: bool = false) -> void:
	if force or absf(stamina - _last_stamina_report) >= 0.4:
		_last_stamina_report = stamina
		stamina_changed.emit(stamina)
