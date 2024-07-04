extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -600.0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

var pid: int
var nametag: String:
	get:
		return $Nametag.text
	set(val):
		$Nametag.text = val

var playtime_counter: float = 0.0
var playtime_interval: float = 1.0
var playtime: float = 0.0:
	set(val):
		playtime = val
		if multiplayer.is_server():
			set_playtime. rpc (val)
		else:
			$Playtime.text = "%.1f" % val

@rpc
func set_playtime(pt: float):
	playtime = pt

var jump_requested: bool = false
var x_movement: float = 0.0

var last_x_input: float

func _ready():
	if multiplayer.get_unique_id() == pid:
		$Camera2D.make_current()

@rpc("any_peer")
func do_a_jump():
	if multiplayer.get_remote_sender_id() != pid:
		return
	jump_requested = true
	
@rpc("any_peer")
func set_x_movement(amount: float):
	if multiplayer.get_remote_sender_id() != pid:
		return
	x_movement = clampf(amount, -1.0, 1.0)

func _unhandled_input(event):
	if multiplayer.get_unique_id() != pid:
		return
	
	if event.is_action_pressed(&"jump"):
		if multiplayer.is_server():
			jump_requested = true
		else:
			do_a_jump.rpc_id(1)

func _process(delta):
	if multiplayer.is_server():
		playtime_counter += delta
		if playtime_counter >= playtime_interval:
			playtime += playtime_counter
			playtime_counter = 0.0
	
	if multiplayer.get_unique_id() != pid:
		return
	
	# local player controls
	var x_input := Input.get_axis("ui_left", "ui_right")
	if x_input != last_x_input:
		if multiplayer.is_server():
			x_movement = clampf(x_input, -1.0, 1.0)
		else:
			set_x_movement.rpc_id(1, x_input)
		last_x_input = x_input

func _physics_process(delta):
	if not multiplayer.is_server():
		return
		
	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta
		
	if jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
	jump_requested = false
	
	if x_movement:
		velocity.x = move_toward(velocity.x, x_movement * SPEED, SPEED * .8)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * .8)

	move_and_slide()
