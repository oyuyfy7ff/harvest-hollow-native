extends Node3D

const PLAYER_SPEED := 4.0
const FARM_SIZE := 7

var state: OfflineState
var player: CharacterBody3D
var camera: Camera3D
var plots_root: Node3D
var status_label: Label

func _ready() -> void:
    state = OfflineState.new()
    add_child(state)
    _build_world()
    _build_player()
    _build_camera()
    _build_minimal_status()
    _refresh_status()

func _build_world() -> void:
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#9bd2c0")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#fff4dc")
    env.ambient_light_energy = 0.8
    environment.environment = env
    add_child(environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
    sun.light_energy = 1.0
    add_child(sun)

    var ground := MeshInstance3D.new()
    var ground_mesh := PlaneMesh.new()
    ground_mesh.size = Vector2(32.0, 32.0)
    ground.mesh = ground_mesh
    ground.material_override = _material(Color("#77a85d"))
    add_child(ground)

    plots_root = Node3D.new()
    plots_root.name = "Plots"
    add_child(plots_root)
    for z in range(-2, 3):
        for x in range(-3, 4):
            _create_plot(Vector3(x * 1.25, 0.04, z * 1.25), "%d:%d" % [x, z])

func _create_plot(position: Vector3, plot_id: String) -> void:
    var body := StaticBody3D.new()
    body.position = position
    body.set_meta("plot_id", plot_id)
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.05, 0.08, 1.05)
    mesh.mesh = box
    mesh.material_override = _material(Color("#8a5c3d"))
    body.add_child(mesh)
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.05, 0.08, 1.05)
    collider.shape = shape
    body.add_child(collider)
    plots_root.add_child(body)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.position = state.player_position
    var mesh := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.height = 1.6
    capsule.radius = 0.35
    mesh.mesh = capsule
    mesh.material_override = _material(Color("#4b72b8"))
    player.add_child(mesh)
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.height = 1.6
    shape.radius = 0.35
    collider.shape = shape
    player.add_child(collider)
    add_child(player)

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.position = Vector3(8.0, 10.0, 10.0)
    camera.look_at_from_position(camera.position, Vector3.ZERO)
    add_child(camera)

func _build_minimal_status() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var safe_area := Control.new()
    safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    safe_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(safe_area)
    status_label = Label.new()
    status_label.position = Vector2(24.0, 20.0)
    status_label.size = Vector2(520.0, 72.0)
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.add_theme_font_size_override("font_size", 24)
    status_label.add_theme_color_override("font_color", Color("#fff8e9"))
    safe_area.add_child(status_label)

func _physics_process(_delta: float) -> void:
    if not player:
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    player.velocity = Vector3(input_vector.x, 0.0, input_vector.y) * PLAYER_SPEED
    player.move_and_slide()
    state.player_position = player.position
    if Input.is_action_just_pressed("interact"):
        _interact_nearby_plot()
    _refresh_status()

func _interact_nearby_plot() -> void:
    var closest: Node3D
    var distance := 1.6
    for plot in plots_root.get_children():
        var current_distance := player.position.distance_to(plot.position)
        if current_distance < distance:
            closest = plot
            distance = current_distance
    if not closest:
        return
    var plot_id: String = closest.get_meta("plot_id", "")
    if state.plots.has(plot_id):
        state.harvest_plot(plot_id)
    else:
        state.plant_plot(plot_id)
    _refresh_status()

func _refresh_status() -> void:
    if status_label and state:
        status_label.text = "Harvest Hollow  |  วันที่ %d  |  เหรียญ %d\nแตะ/กด E เพื่อปลูกหรือเก็บเกี่ยว" % [state.day, state.coins]

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 1.0
    return material
