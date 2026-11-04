extends Node3D
## Harvest Hollow Native - offline 3D farm prototype (Godot 4).

const OfflineStateScript := preload("res://scripts/offline_state.gd")

const PLAYER_SPEED := 4.0
const GROUND_HALF_SIZE := 16.0
const PLOT_COLUMNS := 7
const PLOT_ROWS := 5
const PLOT_SPACING := 1.25
const INTERACT_RANGE := 1.6
const CAMERA_OFFSET := Vector3(8.0, 10.0, 10.0)
const AUTOSAVE_SECONDS := 5.0
const JOYSTICK_RADIUS := 90.0
const JOYSTICK_DEADZONE := 0.15
const INTERACT_BUTTON_RADIUS := 80.0
const INTERACT_BUTTON_MARGIN := 150.0

var state: Node
var player: CharacterBody3D
var camera: Camera3D
var status_label: Label
var message_label: Label
var overlay: Control

var plot_nodes: Dictionary = {}  # plot_id -> StaticBody3D
var crop_nodes: Dictionary = {}  # plot_id -> MeshInstance3D

var _autosave_timer := 0.0
var _last_saved_position := Vector3.INF
var _message_time := 0.0

# Touch controls
var _joystick_index := -1
var _joystick_origin := Vector2.ZERO
var _joystick_position := Vector2.ZERO
var _touch_move := Vector2.ZERO


func _ready() -> void:
	_ensure_input_actions()

	state = OfflineStateScript.new()
	state.name = "OfflineState"
	add_child(state)  # _ready of the state node loads the save

	_build_world()
	_build_plots()
	_build_player()
	_build_camera()
	_build_hud()
	_restore_crops()
	_refresh_status()
	get_viewport().size_changed.connect(overlay.queue_redraw)


# ---------------------------------------------------------------- input ----

## Make sure every action exists with keyboard keys, including the arrow keys
## (project.godot binds Left/Right to the wrong keycodes).
func _ensure_input_actions() -> void:
	var bindings := {
		&"move_left": [KEY_A, KEY_LEFT],
		&"move_right": [KEY_D, KEY_RIGHT],
		&"move_up": [KEY_W, KEY_UP],
		&"move_down": [KEY_S, KEY_DOWN],
		&"interact": [KEY_E, KEY_SPACE],
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		for keycode in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and not event.is_echo():
		_interact()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _is_on_interact_button(touch.position):
				_interact()
			elif _joystick_index == -1 and touch.position.x < _viewport_size().x * 0.6:
				_joystick_index = touch.index
				_joystick_origin = touch.position
				_joystick_position = touch.position
				_touch_move = Vector2.ZERO
		elif touch.index == _joystick_index:
			_joystick_index = -1
			_touch_move = Vector2.ZERO
		overlay.queue_redraw()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _joystick_index:
			_joystick_position = drag.position
			var offset := (_joystick_position - _joystick_origin) / JOYSTICK_RADIUS
			offset = offset.limit_length(1.0)
			_touch_move = offset if offset.length() > JOYSTICK_DEADZONE else Vector2.ZERO
			overlay.queue_redraw()


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _interact_button_center() -> Vector2:
	var size := _viewport_size()
	return Vector2(size.x - INTERACT_BUTTON_MARGIN, size.y - INTERACT_BUTTON_MARGIN)


func _is_on_interact_button(position: Vector2) -> bool:
	return position.distance_to(_interact_button_center()) <= INTERACT_BUTTON_RADIUS * 1.2


# ---------------------------------------------------------------- world ----

func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.53, 0.78, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(GROUND_HALF_SIZE * 2.0, GROUND_HALF_SIZE * 2.0)
	ground.mesh = ground_mesh
	ground.material_override = _make_material(Color(0.36, 0.62, 0.27))
	add_child(ground)


func _build_plots() -> void:
	var half_cols := PLOT_COLUMNS / 2
	var half_rows := PLOT_ROWS / 2
	for gx in range(-half_cols, half_cols + 1):
		for gz in range(-half_rows, half_rows + 1):
			var plot_id := "%d:%d" % [gx, gz]
			var body := StaticBody3D.new()
			body.name = "Plot_%d_%d" % [gx + half_cols, gz + half_rows]
			body.set_meta("plot_id", plot_id)
			body.position = Vector3(gx * PLOT_SPACING, 0.05, gz * PLOT_SPACING)
			# Plots are interaction targets only; keep them out of the player's collision mask.
			body.collision_layer = 2
			body.collision_mask = 0

			var mesh_instance := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.0, 0.1, 1.0)
			mesh_instance.mesh = box
			mesh_instance.material_override = _make_material(Color(0.42, 0.28, 0.16))
			body.add_child(mesh_instance)

			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(1.0, 0.1, 1.0)
			shape.shape = box_shape
			body.add_child(shape)

			add_child(body)
			plot_nodes[plot_id] = body


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	player.collision_layer = 1
	player.collision_mask = 1

	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	mesh_instance.mesh = capsule
	mesh_instance.material_override = _make_material(Color(0.2, 0.4, 0.9))
	player.add_child(mesh_instance)

	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.35
	capsule_shape.height = 1.4
	shape.shape = capsule_shape
	player.add_child(shape)

	add_child(player)
	var start: Vector3 = state.player_position
	start.y = 0.8
	start.x = clampf(start.x, -GROUND_HALF_SIZE + 1.0, GROUND_HALF_SIZE - 1.0)
	start.z = clampf(start.z, -GROUND_HALF_SIZE + 1.0, GROUND_HALF_SIZE - 1.0)
	player.position = start


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 55.0
	add_child(camera)  # must be inside the tree before look_at()
	camera.make_current()
	_update_camera()


func _update_camera() -> void:
	camera.global_position = player.global_position + CAMERA_OFFSET
	camera.look_at(player.global_position, Vector3.UP)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_touch_controls)
	layer.add_child(overlay)

	status_label = Label.new()
	status_label.position = Vector2(16, 12)
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(status_label)

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message_label.position.y = 70
	message_label.add_theme_font_size_override("font_size", 28)
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.add_theme_constant_override("outline_size", 6)
	message_label.visible = false
	layer.add_child(message_label)


func _draw_touch_controls() -> void:
	var size := _viewport_size()
	var font := ThemeDB.fallback_font

	# Joystick: faint resting ring, or the live one under the finger.
	if _joystick_index == -1:
		var rest := Vector2(180.0, size.y - 160.0)
		overlay.draw_arc(rest, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
	else:
		overlay.draw_arc(_joystick_origin, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
		var knob := _joystick_origin + (_joystick_position - _joystick_origin).limit_length(JOYSTICK_RADIUS)
		overlay.draw_circle(knob, 34.0, Color(1, 1, 1, 0.45))

	# Interact button
	var center := _interact_button_center()
	overlay.draw_circle(center, INTERACT_BUTTON_RADIUS, Color(0.1, 0.1, 0.1, 0.45))
	overlay.draw_arc(center, INTERACT_BUTTON_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.7), 4.0)
	overlay.draw_string(font, center + Vector2(-14, 16), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.WHITE)


func _refresh_status() -> void:
	status_label.text = "วัน %d  |  เหรียญ %d\nกด E / ปุ่ม E เพื่อปลูกหรือเก็บเกี่ยว" % [state.day, state.coins]


func _show_message(text: String) -> void:
	message_label.text = text
	message_label.visible = true
	_message_time = 1.6


# ----------------------------------------------------------------- loop ----

func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message_label.visible = false
	_update_camera()


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	input_vector += _touch_move
	input_vector = input_vector.limit_length(1.0)

	# Move relative to the camera so "up" always means "away from the screen".
	var forward := Vector3(-CAMERA_OFFSET.x, 0.0, -CAMERA_OFFSET.z).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var direction := right * input_vector.x - forward * input_vector.y

	player.velocity = direction * PLAYER_SPEED
	player.move_and_slide()

	var pos := player.position
	pos.x = clampf(pos.x, -GROUND_HALF_SIZE + 1.0, GROUND_HALF_SIZE - 1.0)
	pos.z = clampf(pos.z, -GROUND_HALF_SIZE + 1.0, GROUND_HALF_SIZE - 1.0)
	pos.y = 0.8
	player.position = pos

	# Saving every physics frame would rewrite the save file ~60 times a second.
	# Instead save at most every few seconds, and only when the player moved.
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SECONDS:
		_autosave_timer = 0.0
		_save_if_moved()


func _save_if_moved() -> void:
	if player.position.distance_to(_last_saved_position) < 0.05:
		return
	state.player_position = player.position
	_last_saved_position = player.position
	state.save_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST, \
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if is_instance_valid(player) and is_instance_valid(state):
				state.player_position = player.position
				_last_saved_position = player.position
				state.save_game()


# ---------------------------------------------------------- interaction ----

func _interact() -> void:
	var plot_id := _nearest_plot_id()
	if plot_id == "":
		_show_message("ไม่มีแปลงใกล้ตัว")
		return

	if state.plots.has(plot_id):
		if state.harvest_plot(plot_id):
			_remove_crop(plot_id)
			_show_message("เก็บเกี่ยวแล้ว +1 เหรียญ")
	elif state.plant_plot(plot_id):
		_add_crop(plot_id)
		_show_message("ปลูกหัวผักกาดแล้ว")

	state.player_position = player.position
	_last_saved_position = player.position
	_refresh_status()


func _nearest_plot_id() -> String:
	var best_id := ""
	var best_distance := INTERACT_RANGE
	var player_flat := Vector2(player.position.x, player.position.z)
	for plot_id in plot_nodes:
		var plot: Node3D = plot_nodes[plot_id]
		var distance := player_flat.distance_to(Vector2(plot.position.x, plot.position.z))
		if distance <= best_distance:
			best_distance = distance
			best_id = plot_id
	return best_id


func _restore_crops() -> void:
	for plot_id in state.plots:
		if plot_nodes.has(plot_id):
			_add_crop(plot_id)


func _add_crop(plot_id: String) -> void:
	if crop_nodes.has(plot_id) or not plot_nodes.has(plot_id):
		return
	var crop := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	crop.mesh = sphere
	crop.material_override = _make_material(Color(0.85, 0.75, 0.9))
	crop.position = Vector3(0.0, 0.3, 0.0)
	plot_nodes[plot_id].add_child(crop)
	crop_nodes[plot_id] = crop


func _remove_crop(plot_id: String) -> void:
	if crop_nodes.has(plot_id):
		crop_nodes[plot_id].queue_free()
		crop_nodes.erase(plot_id)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
