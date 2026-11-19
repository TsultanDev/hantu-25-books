extends Node3D
## A single lost book. Bobs, spins, glows, and can be collected.

signal collected(book)

@onready var glow_mesh: MeshInstance3D = $Glow
@onready var book_light: OmniLight3D = $BookLight
@onready var pages: MeshInstance3D = $Pages

var is_collected := false
var _time := 0.0
var _base_y := -999.0
var _glow_material: ShaderMaterial

func _ready() -> void:
	_time = randf() * TAU
	_glow_material = glow_mesh.material_override.duplicate() as ShaderMaterial
	glow_mesh.material_override = _glow_material
	book_light.light_energy = 0.0
	book_light.visible = false

func _process(delta: float) -> void:
	if is_collected:
		return
	if _base_y < -100.0:
		_base_y = position.y
	_time += delta
	position.y = _base_y + sin(_time * 2.0) * 0.055
	rotation.y += delta * 0.75
	rotation.z = sin(_time * 1.3) * 0.04
	if _glow_material:
		_glow_material.set_shader_parameter("pulse", 0.85 + sin(_time * 2.6) * 0.18)
	if book_light.visible:
		book_light.light_energy = 1.2 + sin(_time * 5.0) * 0.2

func set_near(near: bool) -> void:
	if is_collected:
		return
	book_light.visible = near
	book_light.light_energy = 1.2 if near else 0.0

func collect() -> void:
	if is_collected:
		return
	is_collected = true
	book_light.light_energy = 0.0
	book_light.visible = false
	collected.emit(self)
	var t := create_tween()
	t.set_parallel()
	t.tween_property(self, "position:y", position.y + 0.9, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation", rotation + Vector3(0.0, 5.0, 0.6), 0.55)
	t.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(glow_mesh, "scale", Vector3(3.0, 3.0, 3.0), 0.3)
	t.chain().tween_callback(queue_free)
