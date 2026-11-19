extends Node
## Headless smoke test. Run with:
## godot --headless --path . res://tests/smoke_test.tscn

var failures: Array[String] = []

func _ready() -> void:
	await _run()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		failures.append(message)
		printerr("  FAIL ", message)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	print("== level ==")
	_check(main.map_w > 0 and main.map_h > 0, "map loaded (%dx%d)" % [main.map_w, main.map_h])
	_check(main.total_books == 25, "25 books spawned (got %d)" % main.total_books)
	_check(main.book_spots.size() == 25, "25 book spots in map")
	_check(main.state == main.State.MENU, "starts in menu")
	_check(main.player != null, "player spawned")
	_check(main.ghost != null, "ghost spawned")

	var all_reachable := true
	for cell in main.book_spots:
		var path: Array = main.find_path(main.spawn_pos, main.cell_to_world(cell))
		if path.is_empty():
			all_reachable = false
			printerr("    unreachable book cell: ", cell)
	_check(all_reachable, "every book is reachable from spawn")
	_check(not main.find_path(main.spawn_pos, main.exit_pos).is_empty(), "exit reachable")
	_check(not main.find_path(main.spawn_pos, main.ghost_start).is_empty(), "ghost spawn reachable")
	_check(main.find_path(main.spawn_pos, main.cell_to_world(Vector2i(0, 0))).size() > 0,
		"pathfinding tolerates solid targets")

	print("== audio ==")
	_check(Sfx.ambience.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambience loops")
	_check(Sfx.heartbeat.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "heartbeat loops")
	_check(Sfx.chase.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "chase loop")
	_check(main.ghost.whisper.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "whisper loops")

	print("== start ==")
	main._on_start_pressed()
	await get_tree().create_timer(1.0).timeout
	_check(main.state == main.State.PLAYING, "game started")

	print("== ghost vision ==")
	var ghost = main.ghost
	ghost.global_position = main.cell_to_world(Vector2i(17, 8))
	ghost.facing = Vector3(0, 0, 1)
	ghost._path.clear()
	main.player.global_position = main.cell_to_world(Vector2i(17, 13)) + Vector3(0, 0.1, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(ghost.is_chasing(), "ghost chases player it can see (mode=%d)" % ghost.mode)

	print("== obstacle breaks vision ==")
	ghost.active = false
	ghost.mode = ghost.Mode.PATROL
	ghost.global_position = main.cell_to_world(Vector2i(5, 4))
	ghost.facing = Vector3(0, 0, 1)
	main.player.global_position = main.cell_to_world(Vector2i(5, 9)) + Vector3(0, 0.1, 0)
	ghost.active = true
	ghost._path.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not ghost.is_chasing(), "ghost does not see through walls")
	ghost.active = false

	print("== collect all books ==")
	var misses := 0
	for book in main.books:
		if not is_instance_valid(book) or book.is_collected:
			continue
		main.player.global_position = Vector3(book.global_position.x, 0.1, book.global_position.z + 1.5)
		await get_tree().physics_frame
		main._update_interaction()
		if main.nearest_book != book:
			misses += 1
			printerr("    could not interact with book at ", book.global_position)
			continue
		main.try_interact()
		await get_tree().process_frame
		if main.exit_open:
			break
	_check(main.collected_books == 25, "all 25 books collected (got %d, misses %d)" % [main.collected_books, misses])
	_check(main.exit_open, "exit unlocked at 25 books")

	print("== escape ==")
	main.player.global_position = main.exit_pos + Vector3(0, 0.1, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main.state == main.State.WON, "reaching the exit wins (state=%d)" % main.state)

	if failures.is_empty():
		print("ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		printerr("%d CHECK(S) FAILED" % failures.size())
		get_tree().quit(1)
