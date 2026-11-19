extends Node3D
## HANTU. It patrols, and only hunts what falls inside its gaze.

signal caught_player
signal spotted
signal chase_started
signal chase_stopped

const WHISPER := preload("res://assets/audio/whisper.wav")

enum Mode { DORMANT, PATROL, SEARCH, CHASE }

@export var patrol_speed := 1.55
@export var chase_speed := 4.25
@export var search_speed := 2.2
@export var vision_range := 18.0
@export var chase_vision := 26.0
@export var field_of_view := 110.0
@export var catch_distance := 1.55

@onready var body_mesh: MeshInstance3D = $Body
@onready var gaze: Node3D = $Gaze
@onready var glow: OmniLight3D = $Glow
@onready var whisper: AudioStreamPlayer3D = $Whisper

var game: Node
var mode := Mode.DORMANT
var active := false
var enraged := false
var facing := Vector3(0, 0, -1)

var _path: Array[Vector3] = []
var _path_index := 0
var _repath_timer := 0.0
var _lost_timer := 0.0
var _search_timer := 0.0
var _idle_timer := 0.0
var _last_seen := Vector3.ZERO
var _hover_time := 0.0
var _base_y := 0.2
var _chase_speed := 4.25
var _material: ShaderMaterial
var _tint := Color(0.72, 0.95, 0.86)
var _target_tint := Color(0.72, 0.95, 0.86)
var _whisper_started := false

func _ready() -> void:
	_material = body_mesh.material_override as ShaderMaterial
	whisper.stream = Sfx.loop_stream(WHISPER)
	Sfx.loop_stream(whisper.stream)
	whisper.play()
	whisper.volume_db = -30.0
	_chase_speed = chase_speed

func setup(p_game: Node) -> void:
	game = p_game

func activate() -> void:
	active = true
	mode = Mode.PATROL
	_whisper_started = true
	whisper.play()
	whisper.volume_db = -13.0
	_pick_patrol()

func enrage() -> void:
	enraged = true
	chase_speed = 5.0
	_chase_speed = chase_speed
	vision_range = 24.0
	chase_vision = 30.0
	_target_tint = Color(1.0, 0.55, 0.48)
	if mode != Mode.CHASE:
		mode = Mode.CHASE
		_last_seen = game.player.global_position
		_repath_to(_last_seen)
	chase_started.emit()
	whisper.volume_db = -7.0

func is_chasing() -> bool:
	return mode == Mode.CHASE

func is_alerted() -> bool:
	return mode == Mode.CHASE or mode == Mode.SEARCH

func _physics_process(delta: float) -> void:
	_animate(delta)
	if not active or game == null or not game.is_playing():
		whisper.volume_db = lerpf(whisper.volume_db, -30.0, delta * 2.0)
		return
	var player = game.player
	if player == null:
		return
	var player_pos: Vector3 = player.global_position
	var dist := _flat_distance(global_position, player_pos)

	if dist <= catch_distance and _can_see(player):
		_catch()
		return

	var sees := _can_see(player)
	if sees:
		if mode != Mode.CHASE:
			mode = Mode.CHASE
			_lost_timer = 0.0
			_repath_timer = 0.0
			spotted.emit()
			chase_started.emit()
			whisper.volume_db = -6.0
		_last_seen = player_pos
		_lost_timer = 0.0
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_to(player_pos)
			_repath_timer = 0.35
	else:
		if mode == Mode.CHASE:
			_lost_timer += delta
			whisper.volume_db = lerpf(whisper.volume_db, -12.0, delta * 2.0)
			if _lost_timer > 4.5:
				mode = Mode.SEARCH
				_search_timer = 7.5
				_repath_to(_last_seen)
				chase_stopped.emit()
		elif mode == Mode.SEARCH:
			_search_timer -= delta
			if _search_timer <= 0.0:
				_begin_patrol()

	match mode:
		Mode.CHASE:
			_move_path(delta, _chase_speed)
		Mode.SEARCH:
			_move_path(delta, search_speed)
		Mode.PATROL:
			_move_path(delta, patrol_speed)

func _catch() -> void:
	if mode == Mode.DORMANT:
		return
	active = false
	mode = Mode.DORMANT
	whisper.volume_db = -60.0
	caught_player.emit()

func _can_see(player) -> bool:
	var eye := global_position + Vector3(0.0, 2.35, 0.0)
	var target: Vector3 = player.global_position + Vector3(0.0, 1.45, 0.0)
	var to := target - eye
	var d := to.length()
	var vision := chase_vision if mode == Mode.CHASE or enraged else vision_range
	if d > vision:
		return false
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.01:
		var dir := flat.normalized()
		var look := Vector3(facing.x, 0.0, facing.z).normalized()
		if look.angle_to(dir) > deg_to_rad(field_of_view * 0.5) and d > 3.2:
			return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, target, 1)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	return hit.is_empty()

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _begin_patrol() -> void:
	mode = Mode.PATROL
	_pick_patrol()

func _pick_patrol() -> void:
	if game == null:
		return
	var best := Vector3.ZERO
	var best_score := -1.0
	for i in 8:
		var cell: Vector2i = game.random_floor_cell()
		var pos: Vector3 = game.cell_to_world(cell)
		var d := _flat_distance(global_position, pos)
		if d < 7.0:
			continue
		var score := d + randf() * 10.0
		if score > best_score:
			best_score = score
			best = pos
	if best_score < 0.0:
		best = game.cell_to_world(game.random_floor_cell())
	_repath_to(best)
	_idle_timer = 0.0

func _repath_to(world_pos: Vector3) -> void:
	if game == null:
		return
	_path = game.find_path(global_position, world_pos)
	_path_index = 0
	if _path.size() > 1 and _flat_distance(global_position, _path[0]) < 0.4:
		_path_index = 1

func _move_path(delta: float, speed: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		if mode == Mode.PATROL:
			if _idle_timer <= 0.0:
				_idle_timer = randf_range(1.0, 2.8)
			_idle_timer -= delta
			facing = facing.rotated(Vector3.UP, delta * 0.55)
			if _idle_timer <= 0.0:
				_pick_patrol()
		elif mode == Mode.SEARCH:
			facing = facing.rotated(Vector3.UP, delta * 0.8)
		return
	var target := _path[_path_index]
	var flat_target := Vector3(target.x, global_position.y, target.z)
	var to := flat_target - global_position
	to.y = 0.0
	if to.length() < 0.28:
		_path_index += 1
		if _path_index >= _path.size():
			_path.clear()
		return
	var dir := to.normalized()
	global_position += dir * speed * delta
	var smooth := 1.0 - exp(-delta * 8.0)
	facing = Vector3(facing.x, 0.0, facing.z).slerp(dir, smooth).normalized()

func _animate(delta: float) -> void:
	_hover_time += delta
	global_position.y = _base_y + sin(_hover_time * 1.25) * 0.07
	body_mesh.position.y = 2.05 + sin(_hover_time * 1.7) * 0.10
	body_mesh.position.x = sin(_hover_time * 0.9) * 0.06
	gaze.rotation.y = atan2(-facing.x, -facing.z)
	_tint = _tint.lerp(_target_tint, 1.0 - exp(-delta * 2.0))
	if _material:
		_material.set_shader_parameter("tint", _tint)
		var target_intensity := 1.55 if mode == Mode.CHASE else 1.0
		var current: float = _material.get_shader_parameter("intensity")
		_material.set_shader_parameter("intensity", lerpf(current, target_intensity, 1.0 - exp(-delta * 3.0)))
	var pulse := 0.95 + sin(_hover_time * 2.4) * 0.2
	if mode == Mode.CHASE:
		pulse += 0.7 + randf() * 0.25
	glow.light_energy = pulse
	if active:
		var target_db := -6.0 if mode == Mode.CHASE else -13.0
		whisper.volume_db = lerpf(whisper.volume_db, target_db, 1.0 - exp(-delta * 2.0))
