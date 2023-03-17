extends CharacterBody3D


signal player_death


const MOUSE_SENS = Vector2(0.0025, 0.0025)
const GRAVITY = 30.0
const MOVE_SPEED = 10.0
const JUMP_POWER = 12.0
const RESPAWN_TIME = 3.0
const IFRAME_TIME = 1.0
const FOOTSTEP_OFFSET = 3.0

var respawn_timer := 0.0
var iframe_timer := 0.0
var is_active := true
var is_vulnerable := true
var last_footstep_pos: Vector3 = Vector3.ZERO

# Network values for updating remote player positions
var has_next_transform := false
var next_position := Vector3.ZERO
var next_rotation := Vector3.ZERO


@onready var head: Node3D = $"%Head"
@onready var hitscan: RayCast3D = $"%Hitscan"
@onready var camera: Camera3D = $"%Camera3D"
@onready var footsteps: Node = $"%Footsteps"
@onready var shooting: Node = $"%Shooting"


func _ready() -> void:
	# We want finer control of the camera node, so it gets set as a top level node with interpolation disabled
	camera.set_as_top_level(true)
	# camera.set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)


# Determine whther or not we should use keypresses to control this instance. Will return true if
# this player object is our own. Will return false otherwise, or if we are in a menu.
func should_control() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if not get_multiplayer().has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not should_control():
		return
	if event is InputEventMouseMotion:
		handle_mouse_movement(event as InputEventMouseMotion)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shoot"):
		if is_active:
			shoot()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if has_next_transform:
		position = next_position
		rotation = Vector3(0, next_rotation.y, 0)
		head.rotation = Vector3(next_rotation.x, 0, 0)
		has_next_transform = false

	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			is_active = true
	else:
		if iframe_timer > 0.0:
			iframe_timer -= delta
			if iframe_timer <= 0.0:
				is_vulnerable = true

		if (not get_multiplayer().has_multiplayer_peer()) or is_multiplayer_authority():
			var wishdir := Vector2.ZERO
			var jump_pressed := false
			if should_control():
				wishdir = Input.get_vector("move_left", "move_right", "move_backwards", "move_forwards")
				jump_pressed = Input.is_action_just_pressed("jump")

			var forward_vector := Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
			var right_vector := Vector3.FORWARD.rotated(Vector3.UP, rotation.y - PI / 2)

			var move_vector := wishdir.x * right_vector + wishdir.y * forward_vector

			velocity.x = move_vector.x * MOVE_SPEED
			velocity.z = move_vector.z * MOVE_SPEED

			var jumping := false

			if is_on_floor() and jump_pressed:
				jumping = true
				velocity.y = JUMP_POWER

			velocity.y -= delta * GRAVITY
			set_velocity(velocity)
			set_floor_snap_length(0.0 if jumping else 1.0)
			set_up_direction(Vector3.UP)
			set_floor_stop_on_slope_enabled(true)
			move_and_slide()
			velocity = velocity

	if is_on_floor() and (position - last_footstep_pos).length() > FOOTSTEP_OFFSET:
		last_footstep_pos = position
		var stream_player := footsteps.get_children()[randf_range(0, footsteps.get_child_count())] as AudioStreamPlayer3D
		stream_player.play()

	if get_multiplayer().has_multiplayer_peer() and is_multiplayer_authority():
		rpc("set_network_transform", position, head.global_rotation)


func _process(_delta: float) -> void:
	# Manually set the camera's position to the interpolated position of the player, but don't change the rotation
	var interp_position := get_global_transform().origin
	camera.global_position = interp_position + head.position


@rpc("unreliable", "any_peer") func set_network_transform(new_position: Vector3, new_rotation: Vector3):
	has_next_transform = true
	next_position = new_position
	next_rotation = new_rotation


func handle_mouse_movement(event: InputEventMouseMotion) -> void:
	var relative := event.relative

	var window_size := get_window().get_size()
	var base_size := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")
	)

	# Because of the 2D scaling mode, the game "scales" our mouse input to match the current window size. That means
	# if you make the window bigger, your mouse inputs will be relatively smaller. We don't want this, since that
	# doesn't make sense for 3D mouse look. So here, we "un-scale" it back to normal
	var input_scale = min(
			float(window_size.x) / float(base_size.x),
			float(window_size.y) / float(base_size.y)
	)
	relative *= input_scale
	# Correct any rounding error
	relative.x = round(relative.x)
	relative.y = round(relative.y)

	# Get the mouse sensitivity from the config.
	var mouse_sensitivity := (Global.config["mouse_sensitivity"] * MOUSE_SENS) as Vector2

	# Contstrain the y rotation to be within one full rotation.
	rotation.y = wrapf(rotation.y - relative.x * mouse_sensitivity.x, 0, TAU)
	# Constrain the x rotation to be between looking directly down and directly up.
	head.rotation.x = clamp(camera.rotation.x - relative.y * mouse_sensitivity.y, -PI / 2, PI / 2)
	# Update the camera's rotation immediately - since it's not interpolated, the player will see the effects of these
	# changes without needing to wait for the next physics tick (less input lag)
	camera.rotation.y = rotation.y
	camera.rotation.x = head.rotation.x


func on_raycast_hit(peer_id: int):
	var shooter_team_id := Multiplayer.player_info[peer_id].team_id as int
	# The player ID of this instance (the one that got shot) should just be its name.
	if is_vulnerable and Multiplayer.player_info[int(name)].team_id != shooter_team_id:
		rpc("ive_been_hit")
		ive_been_hit()


@rpc("any_peer") func ive_been_hit():
	$Blood.emitting = true
	emit_signal("player_death")
	respawn_timer = RESPAWN_TIME
	iframe_timer = IFRAME_TIME
	is_active = false
	is_vulnerable = false


func shoot():
	var stream_player := shooting.get_children()[randf_range(0, shooting.get_child_count())] as AudioStreamPlayer3D
	stream_player.play()
	hitscan.set_enabled(true)
	hitscan.force_raycast_update()
	if hitscan.is_colliding():
		var hit := hitscan.get_collider()
		if hit.has_method("on_raycast_hit"):
			hit.on_raycast_hit(Multiplayer.get_player_id())
	hitscan.set_enabled(false)
