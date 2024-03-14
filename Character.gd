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
			set_playtime.rpc(val)
		else:
			$Playtime.text = "%.1f" % val

@rpc
func set_playtime(pt: float):
	playtime = pt

var jump_requested: bool = false
var x_movement: float = 0.0

var last_x_input: float

const sync_interval = 1.0/30.0
var sync_seq = 0
var sync_clock: float = 0.0

var state_buffer = []
var state_interp: float = 0.0
var got_initial_state = false
var target_state_buffer_len = 3
var target_state_buffer_len_min = 3

# for dynamic client state buffer limiting
var segment_time: float = 0.0
var segment_length: float = 5.0
var drops_in_segment: int = 0
var drops_threshold: int = 2
var dropless_segments: int = 0
var dropless_threshold: int = 5
var buffer_increases: int = 0

func _ready():
	if multiplayer.get_unique_id() == pid:
		$Camera2D.make_current()
	

func set_player_data(data):
	if data == null:
		playtime = 0.0
		return
	playtime = float(data["playtime"] as String)

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

@rpc("authority", "call_remote", "unreliable")
func sync_state(state):
	if len(state_buffer) < 1:
		got_initial_state = true
		state_interp = 0.0
		state_buffer.append(state)
	elif state["S"] > state_buffer[len(state_buffer) - 1]["S"]:
		state_buffer.append(state)
		if state["S"] > state_buffer[len(state_buffer) - 1]["S"] + 1:
			push_warning("state seq skipped %d" % state["S"] - state_buffer[len(state_buffer) - 1]["S"])
	elif state["S"] < state_buffer[0]["S"]:
		push_warning("state drop %d" % state["S"])
	else:
		var idx = 1
		while idx < len(state_buffer):
			if state["S"] == state_buffer[idx]["S"]:
				push_warning("state dupe %d" % state["S"])
				break
			elif state["S"] < state_buffer[idx]["S"]:
				push_warning("state OOO %d" % state["S"])
				break
			idx += 1

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
	var x_input = Input.get_axis("ui_left", "ui_right")
	if x_input != last_x_input:
		if multiplayer.is_server():
			x_movement = clampf(x_input, -1.0, 1.0)
		else:
			set_x_movement.rpc_id(1, x_input)
		last_x_input = x_input

func _apply_sync_state():
	while state_interp > sync_interval:
		state_interp -= sync_interval
		if len(state_buffer) > 1:
			state_buffer.pop_front()
		else:
			push_warning("state buffer depleted")
			state_interp = 0.0
			break
	
	if len(state_buffer) > 1:
		var overbuffered: int = len(state_buffer) - target_state_buffer_len
		if overbuffered > 0:
			push_warning("dropping %d over-buffered states" % overbuffered)
			drops_in_segment += 1
			state_interp = sync_interval
			state_buffer = state_buffer.slice(overbuffered)	
		position = state_buffer[0]["pos"].lerp(state_buffer[1]["pos"], state_interp / sync_interval)
	elif len(state_buffer) == 1:
		state_interp = 0.0
		position = state_buffer[0]["pos"]
	else:
		if got_initial_state:
			push_warning("state buffer empty")

func _physics_process(delta):
	if not multiplayer.is_server():
		state_interp += delta
		
		# adjust state buffer max based on quality of network
		segment_time += delta
		if segment_time >= segment_length:
			if drops_in_segment == 0:
				dropless_segments += 1
				if dropless_segments > dropless_threshold:
					if target_state_buffer_len > target_state_buffer_len_min:
						target_state_buffer_len -= 1
						print("decreasing state buffer to %d" % target_state_buffer_len)
					dropless_segments = 0
			elif drops_in_segment > drops_threshold:
				dropless_segments = 0
				dropless_threshold += 1
				target_state_buffer_len += 1
				buffer_increases += 1
				print("increasing state buffer to %d" % target_state_buffer_len)
				if buffer_increases > 3:
					buffer_increases = 0
					target_state_buffer_len_min += 1
			
			drops_in_segment = 0
			segment_time = 0.0
			
		_apply_sync_state()
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
	
	
	sync_clock += delta
	if sync_clock > sync_interval:
		if sync_clock > sync_interval:
			sync_seq += 1
			sync_clock -= sync_interval
			if sync_clock > sync_interval:
				push_error("sync interval lagging - resetting sync clock")
				sync_clock = 0.0
		sync_state.rpc({
			"S": sync_seq,
			"pos": position
		})
