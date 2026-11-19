extends Node3D
## HANTU: The 25 Books - main game controller and level builder.

const CELL := 3.0
const WALL_HEIGHT := 4.2
const MAP_PATH := "res://data/map.txt"

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GHOST_SCENE := preload("res://scenes/ghost.tscn")
const BOOK_SCENE := preload("res://scenes/book.tscn")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const WALL_SHADER := preload("res://assets/shaders/wall.gdshader")
const FLOOR_SHADER := preload("res://assets/shaders/floor.gdshader")

enum State { MENU, PLAYING, PAUSED, CAUGHT, WON }

const ROOMS := [
	{"name": "DORMITORY", "rect": Rect2i(2, 2, 13, 4)},
	{"name": "CHAPEL", "rect": Rect2i(20, 2, 13, 4)},
	{"name": "LIBRARY", "rect": Rect2i(2, 7, 13, 4)},
	{"name": "NURSERY", "rect": Rect2i(20, 7, 13, 4)},
	{"name": "KITCHEN", "rect": Rect2i(2, 16, 13, 4)},
	{"name": "STUDY", "rect": Rect2i(20, 16, 13, 4)},
	{"name": "STORAGE", "rect": Rect2i(2, 21, 13, 4)},
	{"name": "WARD", "rect": Rect2i(20, 21, 13, 4)},
]

var state := State.MENU
var map: Array[String] = []
var map_w := 0
var map_h := 0

var wall_cells: Dictionary = {}
var floor_cells: Array[Vector2i] = []
var book_spots: Array[Vector2i] = []
var spawn_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var spawn_pos := Vector3.ZERO
var exit_pos := Vector3.ZERO
var ghost_start := Vector3.ZERO
var astar: AStarGrid2D

var player: CharacterBody3D
var ghost: Node3D
var hud: CanvasLayer
var books: Array = []
var total_books := 25
var collected_books := 0
var exit_open := false

var elapsed := 0.0
var nearest_book: Node3D = null
var _prompt_key := ""
var _starting := false
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _locked_cooldown := 0.0
var _enraged := false

var _flicker_lights: Array = []
var _door_left: Node3D
var _door_right: Node3D
var _exit_light: OmniLight3D
var _exit_sign: Label3D

var mat_wall: ShaderMaterial
var mat_floor: ShaderMaterial
var mat_wood: StandardMaterial3D
var mat_wood_dark: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_paper: StandardMaterial3D
var mat_fixture: StandardMaterial3D
var mat_frame: StandardMaterial3D
var mat_portrait: StandardMaterial3D
var _book_mats: Array = []

func _ready() -> void:
	_rng.seed = 20261115
	Sfx.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_load_map()
	_make_materials()
	_build_environment()
	_build_geometry()
	_build_astar()
	_build_lights()
	_build_props()
	_spawn_books()
	_spawn_exit()
	_spawn_player()
	_spawn_ghost()
	_build_hud()
	state = State.MENU
	hud.set_books(0, total_books)
	hud.set_stamina(player.stamina)
	hud.show_menu()
	Sfx.start_menu()

func is_playing() -> bool:
	return state == State.PLAYING

# ---------------------------------------------------------------------------
# map + navigation
# ---------------------------------------------------------------------------
func _load_map() -> void:
	var text := FileAccess.get_file_as_string(MAP_PATH)
	if text.is_empty():
		push_error("Could not read %s" % MAP_PATH)
		return
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.strip_edges().is_empty():
			continue
		map.append(line)
	map_h = map.size()
	map_w = map[0].length()
	for y in map_h:
		var row := map[y]
		for x in map_w:
			var c := row[x]
			var cell := Vector2i(x, y)
			if c == "#":
				wall_cells[cell] = true
				continue
			floor_cells.append(cell)
			if c == "S":
				spawn_cell = cell
			elif c == "E":
				exit_cell = cell
			elif c == "?":
				book_spots.append(cell)
	if spawn_cell == Vector2i.ZERO:
		spawn_cell = floor_cells[0]
	if exit_cell == Vector2i.ZERO:
		exit_cell = floor_cells[floor_cells.size() - 1]
	spawn_pos = cell_to_world(spawn_cell)
	exit_pos = cell_to_world(exit_cell)
	var ghost_cell := Vector2i(17, 2)
	if wall_cells.has(ghost_cell):
		ghost_cell = floor_cells[0]
	ghost_start = cell_to_world(ghost_cell)

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, map_w, map_h)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for cell in wall_cells.keys():
		astar.set_point_solid(cell, true)

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)

func random_floor_cell() -> Vector2i:
	return floor_cells[_rng.randi_range(0, floor_cells.size() - 1)]

func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var start := world_to_cell(from)
	var finish := world_to_cell(to)
	if astar.is_point_solid(start):
		start = _nearest_floor(start)
	if astar.is_point_solid(finish):
		finish = _nearest_floor(finish)
	if start == finish:
		points.append(cell_to_world(finish))
		return points
	var ids := astar.get_id_path(start, finish)
	for id in ids:
		points.append(cell_to_world(id))
	return points

func _nearest_floor(cell: Vector2i) -> Vector2i:
	for radius in range(1, 10):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := cell + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= map_w or c.y >= map_h:
					continue
				if not wall_cells.has(c):
					return c
	return cell

# ---------------------------------------------------------------------------
# materials / environment / geometry
# ---------------------------------------------------------------------------
func _make_materials() -> void:
	mat_wall = ShaderMaterial.new()
	mat_wall.shader = WALL_SHADER
	mat_floor = ShaderMaterial.new()
	mat_floor.shader = FLOOR_SHADER

	mat_wood = _standard(Color(0.16, 0.11, 0.07), 0.86)
	mat_wood_dark = _standard(Color(0.075, 0.052, 0.035), 0.9)
	mat_metal = _standard(Color(0.12, 0.13, 0.13), 0.55, 0.65)
	mat_dark = _standard(Color(0.045, 0.045, 0.045), 0.95)
	mat_paper = _standard(Color(0.55, 0.52, 0.42), 0.95)
	mat_frame = _standard(Color(0.07, 0.045, 0.028), 0.8)
	mat_fixture = _standard(Color(0.75, 0.66, 0.46), 0.45)
	mat_fixture.emission_enabled = true
	mat_fixture.emission = Color(1.0, 0.82, 0.52)
	mat_fixture.emission_energy_multiplier = 4.0

	mat_portrait = StandardMaterial3D.new()
	mat_portrait.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_portrait.albedo_texture = load("res://HANTU.jpeg")
	mat_portrait.albedo_color = Color(0.6, 0.53, 0.42)
	mat_portrait.cull_mode = BaseMaterial3D.CULL_DISABLED

	for color in [Color(0.34, 0.12, 0.09), Color(0.15, 0.25, 0.15),
			Color(0.2, 0.19, 0.28), Color(0.42, 0.32, 0.14)]:
		_book_mats.append(_standard(color, 0.8))

func _standard(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.007)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.48)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.06, 0.065)
	env.fog_light_energy = 0.7
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.05
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.84
	we.environment = env
	add_child(we)

func _build_geometry() -> void:
	var world_size := Vector3(map_w * CELL, 0.4, map_h * CELL)
	var center := Vector3(world_size.x * 0.5, -0.2, world_size.z * 0.5)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = world_size
	floor_shape.shape = floor_box
	floor_shape.position = center
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var floor_mesh_box := BoxMesh.new()
	floor_mesh_box.size = world_size
	floor_mesh.mesh = floor_mesh_box
	floor_mesh.material_override = mat_floor
	floor_mesh.position = center
	floor_body.add_child(floor_mesh)

	var ceiling := MeshInstance3D.new()
	var ceiling_box := BoxMesh.new()
	ceiling_box.size = Vector3(world_size.x, 0.2, world_size.z)
	ceiling.mesh = ceiling_box
	ceiling.position = Vector3(world_size.x * 0.5, WALL_HEIGHT + 0.1, world_size.z * 0.5)
	var ceiling_mat := _standard(Color(0.055, 0.05, 0.045), 1.0)
	ceiling.material_override = ceiling_mat
	add_child(ceiling)

	var wall_body := StaticBody3D.new()
	wall_body.name = "Walls"
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	add_child(wall_body)
	for y in map_h:
		var x := 0
		var row := map[y]
		while x < map_w:
			if row[x] != "#":
				x += 1
				continue
			var start := x
			while x < map_w and row[x] == "#":
				x += 1
			var run := x - start
			var size := Vector3(run * CELL, WALL_HEIGHT, CELL)
			var pos := Vector3((start + run * 0.5) * CELL, WALL_HEIGHT * 0.5, (y + 0.5) * CELL)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			shape.shape = box
			shape.position = pos
			wall_body.add_child(shape)
			var mesh := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = size
			mesh.mesh = box_mesh
			mesh.material_override = mat_wall
			mesh.position = pos
			wall_body.add_child(mesh)

func _build_lights() -> void:
	for entry in ROOMS:
		var rect: Rect2i = entry["rect"]
		var pos := Vector3((rect.position.x + rect.size.x * 0.5) * CELL, 3.8,
				(rect.position.y + rect.size.y * 0.5) * CELL)
		_add_ceiling_light(pos, Color(1.0, 0.83, 0.62), 3.4, 18.0, 0.8)
	var corridor_spots := [Vector2i(17, 4), Vector2i(17, 13), Vector2i(17, 22),
			Vector2i(5, 13), Vector2i(30, 13)]
	for cell in corridor_spots:
		var pos := cell_to_world(cell) + Vector3(0, 3.8, 0)
		_add_ceiling_light(pos, Color(0.72, 0.84, 0.88), 2.5, 15.0, 1.15)

func _add_ceiling_light(pos: Vector3, color: Color, energy: float, light_range: float, flicker: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.light_specular = 0.25
	light.shadow_enabled = false
	light.omni_range = light_range
	light.omni_attenuation = 1.05
	add_child(light)
	_flicker_lights.append({
		"light": light,
		"base": energy,
		"phase": _rng.randf() * TAU,
		"speed": flicker,
	})
	var fixture := _add_box_mesh(pos + Vector3(0, 0.16, 0), Vector3(0.78, 0.07, 0.52), mat_fixture)
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_props() -> void:
	for entry in ROOMS:
		var rect: Rect2i = entry["rect"]
		var x0 := rect.position.x
		var y0 := rect.position.y
		var north_z := y0 * CELL + 0.34
		_add_shelf(Vector3((x0 + 3.0) * CELL, 0.0, north_z), 0.0)
		_add_shelf(Vector3((x0 + 9.6) * CELL, 0.0, north_z), 0.0)
		_add_portrait(Vector3((x0 + 6.3) * CELL, 2.5, y0 * CELL + 0.09))
		_add_wardrobe(Vector3((x0 + 11.4) * CELL, 0.0, (y0 + 4) * CELL - 0.5), PI)
		_add_crate(Vector3((x0 + 0.9) * CELL, 0.42, (y0 + 3.2) * CELL), _rng.randf_range(0, 0.4))
		_add_crate(Vector3((x0 + 12.0) * CELL, 0.42, (y0 + 0.8) * CELL), _rng.randf_range(0, 0.4))
		_add_chair(Vector3((x0 + 5.2) * CELL, 0.0, (y0 + 2.55) * CELL), _rng.randf_range(-0.6, 0.6))
		_add_chair(Vector3((x0 + 8.8) * CELL, 0.0, (y0 + 0.75) * CELL), _rng.randf_range(2.2, 3.4))
		for i in 4:
			var paper := _add_box_mesh(
				Vector3((x0 + _rng.randf_range(1.5, 12.0)) * CELL, 0.012,
					(y0 + _rng.randf_range(0.5, 3.5)) * CELL),
				Vector3(0.34, 0.008, 0.46), mat_paper,
				_rng.randf_range(0, TAU))
			paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_room_sign(entry)

	# a few loose crates in the corridors
	for cell in [Vector2i(16, 9), Vector2i(18, 18), Vector2i(4, 12), Vector2i(31, 14)]:
		_add_crate(cell_to_world(cell) + Vector3(0.4, 0.42, 0.2), _rng.randf_range(0, 0.6))

func _add_shelf(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_box_to(root, Vector3(0, 1.05, 0), Vector3(2.7, 2.1, 0.09), mat_wood_dark)
	_add_box_to(root, Vector3(-1.33, 1.05, 0.18), Vector3(0.08, 2.1, 0.42), mat_wood_dark)
	_add_box_to(root, Vector3(1.33, 1.05, 0.18), Vector3(0.08, 2.1, 0.42), mat_wood_dark)
	for i in 3:
		var y := 0.35 + i * 0.62
		_add_box_to(root, Vector3(0, y, 0.18), Vector3(2.6, 0.06, 0.4), mat_wood)
		for j in 4:
			var mat: StandardMaterial3D = _book_mats[_rng.randi_range(0, _book_mats.size() - 1)]
			var h := _rng.randf_range(0.22, 0.36)
			_add_box_to(root, Vector3(-1.0 + j * 0.38 + _rng.randf_range(-0.04, 0.04),
					y + 0.04 + h * 0.5, 0.23), Vector3(0.16, h, 0.22), mat)
	_add_static_to(root, Vector3(0, 1.05, 0.16), Vector3(2.7, 2.1, 0.46))

func _add_wardrobe(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_box_to(root, Vector3(0, 1.2, 0), Vector3(1.45, 2.4, 0.62), mat_wood_dark)
	_add_box_to(root, Vector3(-0.36, 1.2, 0.32), Vector3(0.62, 2.25, 0.04), mat_wood)
	_add_box_to(root, Vector3(0.36, 1.2, 0.32), Vector3(0.62, 2.25, 0.04), mat_wood)
	_add_box_to(root, Vector3(0, 2.31, 0.05), Vector3(1.55, 0.08, 0.7), mat_wood_dark)
	_add_static_to(root, Vector3(0, 1.2, 0), Vector3(1.45, 2.4, 0.62))

func _add_crate(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_box_to(root, Vector3.ZERO, Vector3(0.82, 0.82, 0.82), mat_wood)
	_add_box_to(root, Vector3(0, 0.32, 0.415), Vector3(0.7, 0.07, 0.03), mat_wood_dark)
	_add_box_to(root, Vector3(0, -0.32, 0.415), Vector3(0.7, 0.07, 0.03), mat_wood_dark)
	_add_static_to(root, Vector3.ZERO, Vector3(0.82, 0.82, 0.82))

func _add_chair(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_box_to(root, Vector3(0, 0.46, 0), Vector3(0.55, 0.07, 0.55), mat_wood_dark)
	for sx in [-0.22, 0.22]:
		for sz in [-0.22, 0.22]:
			_add_box_to(root, Vector3(sx, 0.23, sz), Vector3(0.06, 0.46, 0.06), mat_wood_dark)
	_add_box_to(root, Vector3(0, 0.85, -0.26), Vector3(0.55, 0.75, 0.07), mat_wood_dark)

func _add_portrait(pos: Vector3) -> void:
	_add_box_mesh(pos + Vector3(0, 0, -0.03), Vector3(1.42, 1.62, 0.08), mat_frame)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.14, 1.34)
	quad.mesh = mesh
	quad.material_override = mat_portrait
	quad.position = pos + Vector3(0, 0, 0.02)
	add_child(quad)

func _add_room_sign(entry: Dictionary) -> void:
	var rect: Rect2i = entry["rect"]
	var left := rect.position.x < 15
	var z := (rect.position.y + 1.5) * CELL
	var x := 48.03 if left else 56.97
	var rot := PI * 0.5 if left else -PI * 0.5
	_add_box_mesh(Vector3(48.01 if left else 56.99, 2.9, z), Vector3(0.05, 0.62, 1.95), mat_frame)
	var label := Label3D.new()
	label.text = String(entry["name"])
	label.font_size = 44
	label.pixel_size = 0.006
	label.modulate = Color(0.82, 0.74, 0.57)
	label.outline_modulate = Color(0.03, 0.025, 0.02)
	label.outline_size = 10
	label.shaded = false
	label.double_sided = true
	label.position = Vector3(x, 2.9, z)
	label.rotation.y = rot
	add_child(label)

# ---------------------------------------------------------------------------
# books / exit
# ---------------------------------------------------------------------------
func _add_table(center: Vector3) -> void:
	_add_static_box(center + Vector3(0, 0.83, 0), Vector3(1.38, 0.09, 0.76), mat_wood)
	for sx in [-0.58, 0.58]:
		for sz in [-0.28, 0.28]:
			_add_box_mesh(center + Vector3(sx, 0.4, sz), Vector3(0.08, 0.8, 0.08), mat_wood_dark)

func _spawn_books() -> void:
	for cell in book_spots:
		var pos := cell_to_world(cell)
		_add_table(pos)
		var book = BOOK_SCENE.instantiate()
		book.position = pos + Vector3(0.0, 1.16, 0.0)
		add_child(book)
		book.collected.connect(_on_book_collected)
		books.append(book)
	total_books = books.size()

func _spawn_exit() -> void:
	var door_x := (exit_cell.x + 0.5) * CELL
	var door_z := float(map_h - 1) * CELL + 0.04
	var frame_mat := mat_metal
	_add_box_mesh(Vector3(door_x - 1.48, 1.78, door_z), Vector3(0.22, 3.55, 0.24), frame_mat)
	_add_box_mesh(Vector3(door_x + 1.48, 1.78, door_z), Vector3(0.22, 3.55, 0.24), frame_mat)
	_add_box_mesh(Vector3(door_x, 3.63, door_z), Vector3(3.2, 0.28, 0.28), frame_mat)

	_door_left = Node3D.new()
	_door_left.position = Vector3(door_x - 1.35, 0.0, door_z)
	add_child(_door_left)
	_add_box_to(_door_left, Vector3(0.68, 1.72, 0.0), Vector3(1.36, 3.35, 0.14), mat_wood_dark)
	_add_box_to(_door_left, Vector3(0.68, 2.35, -0.09), Vector3(1.2, 0.12, 0.04), mat_metal)
	_add_box_to(_door_left, Vector3(0.68, 0.9, -0.09), Vector3(1.2, 0.12, 0.04), mat_metal)
	_add_box_to(_door_left, Vector3(1.24, 1.65, -0.12), Vector3(0.08, 0.3, 0.08), mat_metal)

	_door_right = Node3D.new()
	_door_right.position = Vector3(door_x + 1.35, 0.0, door_z)
	add_child(_door_right)
	_add_box_to(_door_right, Vector3(-0.68, 1.72, 0.0), Vector3(1.36, 3.35, 0.14), mat_wood_dark)
	_add_box_to(_door_right, Vector3(-0.68, 2.35, -0.09), Vector3(1.2, 0.12, 0.04), mat_metal)
	_add_box_to(_door_right, Vector3(-0.68, 0.9, -0.09), Vector3(1.2, 0.12, 0.04), mat_metal)
	_add_box_to(_door_right, Vector3(-1.24, 1.65, -0.12), Vector3(0.08, 0.3, 0.08), mat_metal)

	_add_box_mesh(Vector3(door_x, 3.42, door_z - 0.14), Vector3(1.9, 0.62, 0.1), mat_frame)
	_exit_sign = Label3D.new()
	_exit_sign.text = "EXIT"
	_exit_sign.font_size = 66
	_exit_sign.pixel_size = 0.0075
	_exit_sign.modulate = Color(0.9, 0.28, 0.2)
	_exit_sign.outline_modulate = Color(0.05, 0.0, 0.0)
	_exit_sign.outline_size = 12
	_exit_sign.shaded = false
	_exit_sign.double_sided = true
	_exit_sign.position = Vector3(door_x, 3.42, door_z - 0.21)
	_exit_sign.rotation.y = PI
	add_child(_exit_sign)

	# Faint moonlight beyond the doorway: the way out.
	var outside := MeshInstance3D.new()
	var outside_quad := QuadMesh.new()
	outside_quad.size = Vector2(13.0, 7.5)
	outside.mesh = outside_quad
	var outside_mat := StandardMaterial3D.new()
	outside_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outside_mat.albedo_color = Color(0.26, 0.38, 0.35)
	outside_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	outside.material_override = outside_mat
	outside.position = Vector3(door_x, 3.2, float(map_h) * CELL + 0.6)
	outside.rotation.y = PI
	add_child(outside)

	_exit_light = OmniLight3D.new()
	_exit_light.position = Vector3(door_x, 2.7, door_z + 1.7)
	_exit_light.light_color = Color(0.9, 0.2, 0.12)
	_exit_light.light_energy = 1.2
	_exit_light.light_specular = 0.2
	_exit_light.omni_range = 13.0
	_exit_light.omni_attenuation = 1.3
	add_child(_exit_light)

func _unlock_exit() -> void:
	if exit_open:
		return
	exit_open = true
	_enraged = true
	_exit_light.light_color = Color(0.4, 1.0, 0.55)
	_exit_light.light_energy = 2.1
	_exit_sign.modulate = Color(0.55, 1.0, 0.62)
	Sfx.play_sfx("unlock", -2.0)
	hud.flash_message("THE DOOR IS OPEN — RUN", Color(0.6, 1.0, 0.64), 4.2)
	hud.show_hint("The exit is at the south end of the central hall. It knows you are coming.", 7.0)
	if ghost:
		ghost.enrage()
	var t := create_tween().set_parallel()
	t.tween_property(_door_left, "rotation:y", 1.8, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_door_right, "rotation:y", -1.8, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

# ---------------------------------------------------------------------------
# actors
# ---------------------------------------------------------------------------
func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = spawn_pos + Vector3(0.0, 0.08, 0.0)
	add_child(player)
	player.set_control(false)
	player.stamina_changed.connect(_on_stamina_changed)

func _spawn_ghost() -> void:
	ghost = GHOST_SCENE.instantiate()
	ghost.position = ghost_start
	add_child(ghost)
	ghost.setup(self)
	ghost.spotted.connect(_on_ghost_spotted)
	ghost.chase_started.connect(_on_chase_started)
	ghost.chase_stopped.connect(_on_chase_stopped)
	ghost.caught_player.connect(_on_ghost_caught)

func _build_hud() -> void:
	hud = HUD_SCRIPT.new()
	add_child(hud)
	hud.start_pressed.connect(_on_start_pressed)
	hud.retry_pressed.connect(_restart)
	hud.restart_pressed.connect(_restart)
	hud.resume_pressed.connect(_toggle_pause)
	hud.pause_pressed.connect(_toggle_pause)
	hud.interact_pressed.connect(try_interact)
	hud.move_changed.connect(player.set_move_input)
	hud.sprint_changed.connect(player.set_sprint_held)

# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	_update_flicker()
	if _locked_cooldown > 0.0:
		_locked_cooldown -= delta
	if state == State.MENU:
		hud.set_danger(0.0)
		return
	if state != State.PLAYING:
		return

	elapsed += delta
	var ghost_dist := 0.0
	if ghost:
		ghost_dist = player.global_position.distance_to(ghost.global_position)
	var chasing: bool = ghost.is_chasing() if ghost else false
	var threat := clampf(1.0 - ghost_dist / 17.0, 0.0, 1.0)
	var danger := threat * (1.0 if chasing else 0.42)
	var low := clampf((25.0 - player.stamina) / 25.0, 0.0, 1.0)
	danger = maxf(danger, low * 0.4)
	if exit_open:
		danger = maxf(danger, 0.3)
	hud.set_danger(danger)
	player.set_fear(danger)
	Sfx.set_tension(maxf(danger * 0.92, low * 0.55))

	_update_interaction()
	if exit_open and _flat_dist(player.global_position, exit_pos) < 2.2:
		_win()

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _update_interaction() -> void:
	var best: Node3D = null
	var best_d := 2.7
	var head := player.global_position + Vector3(0, 1.45, 0)
	for book in books:
		if not is_instance_valid(book) or book.is_collected:
			continue
		var d: float = player.global_position.distance_to(book.global_position)
		if d < best_d and _has_los(head, book.global_position):
			best = book
			best_d = d
	if best != nearest_book:
		if nearest_book and is_instance_valid(nearest_book):
			nearest_book.set_near(false)
		nearest_book = best
		if nearest_book:
			nearest_book.set_near(true)
	var near := _flat_dist(player.global_position, exit_pos) < 3.0
	if nearest_book:
		_set_prompt("book", "TAKE THE BOOK", true, "TAKE")
	elif near and exit_open:
		_set_prompt("exit_open", "THE DOOR IS OPEN", false)
	elif near:
		_set_prompt("exit_locked_%d" % collected_books,
				"SEALED  —  %d / %d BOOKS" % [collected_books, total_books], true, "TRY")
	else:
		_set_prompt("", "", false)

func _set_prompt(key: String, text: String, button: bool, label: String = "TAKE") -> void:
	if _prompt_key == key:
		return
	_prompt_key = key
	if key.is_empty():
		hud.hide_prompt()
		hud.set_interact_visible(false)
	else:
		hud.show_prompt(text)
		hud.set_interact_visible(button, label)

func _has_los(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	return hit.is_empty()

func _update_flicker() -> void:
	for entry in _flicker_lights:
		var light: OmniLight3D = entry["light"]
		if not is_instance_valid(light):
			continue
		var base: float = entry["base"]
		var phase: float = entry["phase"]
		var speed: float = entry["speed"]
		var f := 0.84 + 0.11 * sin(_time * speed * 3.1 + phase) \
				+ 0.05 * sin(_time * speed * 8.7 + phase * 1.7)
		if _enraged or state == State.CAUGHT:
			f *= 0.55 + 0.45 * absf(sin(_time * speed * 5.0 + phase))
		if _rng.randf() < 0.0025:
			f *= 0.25
		light.light_energy = base * f

# ---------------------------------------------------------------------------
# interaction / events
# ---------------------------------------------------------------------------
func try_interact() -> void:
	if state != State.PLAYING:
		return
	if nearest_book and is_instance_valid(nearest_book) and not nearest_book.is_collected:
		nearest_book.collect()
		return
	if _flat_dist(player.global_position, exit_pos) < 3.2 and not exit_open:
		if _locked_cooldown <= 0.0:
			_locked_cooldown = 2.2
			Sfx.play_sfx("locked", -2.0)
			hud.flash_message("THE DOOR IS SEALED", Color(0.85, 0.32, 0.22), 2.0)
			player.add_trauma(0.15)

func _on_book_collected(book: Node3D) -> void:
	collected_books += 1
	nearest_book = null
	_prompt_key = ""
	hud.hide_prompt()
	hud.set_interact_visible(false)
	Sfx.play_sfx("book", -3.0, _rng.randf_range(0.96, 1.06))
	player.add_stamina(9.0)
	hud.set_books(collected_books, total_books)
	if collected_books >= total_books:
		_unlock_exit()
	else:
		hud.flash_message("BOOK  %d / %d" % [collected_books, total_books], Color(1.0, 0.82, 0.42), 1.5)

func _on_stamina_changed(value: float) -> void:
	if hud:
		hud.set_stamina(value)

func _on_ghost_spotted() -> void:
	if state != State.PLAYING:
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(120)
	hud.flash_message("IT SEES YOU", Color(0.9, 0.16, 0.12), 1.9)
	hud.show_hint("Break its line of sight. Do not let it get close.", 4.0)
	Sfx.play_stinger()
	player.add_trauma(0.42)

func _on_chase_started() -> void:
	Sfx.set_chase(true)

func _on_chase_stopped() -> void:
	Sfx.set_chase(false)

func _on_ghost_caught() -> void:
	if state != State.PLAYING:
		return
	state = State.CAUGHT
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(600)
	player.set_control(false)
	player.force_look_at(ghost.global_position + Vector3(0.0, 2.2, 0.0))
	player.add_trauma(1.0)
	ghost.active = false
	hud.set_danger(1.0)
	hud.hide_prompt()
	hud.set_interact_visible(false)
	hud.show_jumpscare()
	Sfx.play_jumpscare()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(2.6).timeout
	hud.hide_jumpscare()
	hud.show_end(false, elapsed, collected_books)

func _win() -> void:
	if state != State.PLAYING:
		return
	state = State.WON
	player.set_control(false)
	if ghost:
		ghost.active = false
	hud.set_danger(0.0)
	hud.hide_prompt()
	hud.set_interact_visible(false)
	Sfx.play_win()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.fade_out(0.7)
	await get_tree().create_timer(1.0).timeout
	hud.show_end(true, elapsed, collected_books)

# ---------------------------------------------------------------------------
# menus / state
# ---------------------------------------------------------------------------
func _on_start_pressed() -> void:
	if state != State.MENU or _starting:
		return
	_starting = true
	hud.fade_out(0.3)
	await get_tree().create_timer(0.34).timeout
	if state != State.MENU:
		_starting = false
		return
	state = State.PLAYING
	elapsed = 0.0
	hud.show_gameplay()
	player.set_control(true)
	ghost.activate()
	Sfx.start_game()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_books(0, total_books)
	hud.set_stamina(player.stamina)
	hud.set_danger(0.0)
	hud.flash_message("FIND THE 25 BOOKS", Color(0.92, 0.88, 0.78), 3.0)
	hud.show_hint("Find 25 books. The front door opens only when the last one is found. It only sees what falls in its gaze.", 10.0)
	hud.fade_in(0.8)
	_starting = false

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		if state == State.PLAYING or state == State.PAUSED:
			_toggle_pause()
			get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_E and state == State.PLAYING:
		try_interact()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		player.set_control(false)
		hud.show_pause(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Sfx.set_paused(true)
	elif state == State.PAUSED:
		state = State.PLAYING
		player.set_control(true)
		hud.show_pause(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Sfx.set_paused(false)

func _restart() -> void:
	Sfx.reset()
	AudioServer.set_bus_mute(0, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()

# ---------------------------------------------------------------------------
# small mesh helpers
# ---------------------------------------------------------------------------
func _add_box_mesh(pos: Vector3, size: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	return mi

func _add_static_box(pos: Vector3, size: Vector3, mat: Material, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	return body

func _add_box_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _add_static_to(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body
