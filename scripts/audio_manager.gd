extends Node
## Global audio director: ambience, heartbeat, chase music and one-shots.

const AMBIENCE := preload("res://assets/audio/ambience.wav")
const HEARTBEAT := preload("res://assets/audio/heartbeat.wav")
const CHASE := preload("res://assets/audio/chase.wav")
const WHISPER := preload("res://assets/audio/whisper.wav")
const STINGER := preload("res://assets/audio/stinger.wav")
const SCREAM := preload("res://assets/audio/scream.wav")
const JUMPSCARE := preload("res://assets/audio/jumpscare.wav")
const BOOK := preload("res://assets/audio/book.wav")
const STEP := preload("res://assets/audio/step.wav")
const LOCKED := preload("res://assets/audio/locked.wav")
const UNLOCK := preload("res://assets/audio/unlock.wav")
const WIN := preload("res://assets/audio/win.wav")
const CLICK := preload("res://assets/audio/ui_click.wav")

const SOUNDS := {
	"stinger": STINGER,
	"scream": SCREAM,
	"jumpscare": JUMPSCARE,
	"book": BOOK,
	"step": STEP,
	"locked": LOCKED,
	"unlock": UNLOCK,
	"win": WIN,
	"click": CLICK,
}

var ambience: AudioStreamPlayer
var heartbeat: AudioStreamPlayer
var chase: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _chase_on := false
var _chase_tween: Tween
var _win_tween: Tween
var _heartbeat_on := false

func _ready() -> void:
	ambience = _loop_player(AMBIENCE, -14.0)
	heartbeat = _loop_player(HEARTBEAT, -40.0)
	chase = _loop_player(CHASE, -40.0)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

func _loop_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	loop_stream(stream)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = "Master"
	add_child(p)
	return p

func loop_stream(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return stream

func reset() -> void:
	kill_tweens()
	ambience.stop()
	heartbeat.stop()
	chase.stop()
	_chase_on = false
	_heartbeat_on = false
	for p in _pool:
		p.stop()
	ambience.volume_db = -14.0
	heartbeat.volume_db = -40.0
	chase.volume_db = -40.0
	AudioServer.set_bus_mute(0, false)

func kill_tweens() -> void:
	if _chase_tween and _chase_tween.is_valid():
		_chase_tween.kill()
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()

func start_menu() -> void:
	reset()
	ambience.volume_db = -16.0
	ambience.play()

func start_game() -> void:
	ambience.volume_db = -9.0
	if not ambience.playing:
		ambience.play()
	heartbeat.volume_db = -38.0
	heartbeat.play()
	_heartbeat_on = true

func set_tension(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if not _heartbeat_on:
		return
	var target := lerpf(-38.0, -4.0, pow(value, 1.6))
	heartbeat.volume_db = minf(heartbeat.volume_db + 8.0, target) if target > heartbeat.volume_db else target
	if heartbeat.volume_db > -37.0 and not heartbeat.playing:
		heartbeat.play()

func set_chase(active: bool) -> void:
	if active == _chase_on:
		return
	_chase_on = active
	kill_tweens()
	if active:
		chase.volume_db = -30.0
		chase.play()
		_chase_tween = create_tween()
		_chase_tween.tween_property(chase, "volume_db", -7.0, 0.7)
	else:
		_chase_tween = create_tween()
		_chase_tween.tween_property(chase, "volume_db", -40.0, 1.2)
		_chase_tween.tween_callback(chase.stop)

func play_sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not SOUNDS.has(name):
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = SOUNDS[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func play_stinger() -> void:
	play_sfx("stinger", -2.0)

func play_jumpscare() -> void:
	kill_tweens()
	ambience.stop()
	heartbeat.stop()
	chase.stop()
	_chase_on = false
	_heartbeat_on = false
	play_sfx("jumpscare", 1.0)

func play_win() -> void:
	kill_tweens()
	_win_tween = create_tween()
	_win_tween.tween_property(ambience, "volume_db", -40.0, 1.5)
	_win_tween.parallel().tween_property(chase, "volume_db", -40.0, 0.8)
	_win_tween.parallel().tween_property(heartbeat, "volume_db", -40.0, 0.8)
	_win_tween.tween_callback(chase.stop)
	_win_tween.tween_callback(heartbeat.stop)
	play_sfx("win", -2.0)

func stop_loops() -> void:
	ambience.stop()
	heartbeat.stop()
	chase.stop()
	_chase_on = false
	_heartbeat_on = false

func set_paused(paused: bool) -> void:
	AudioServer.set_bus_mute(0, paused)
