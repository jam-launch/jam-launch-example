extends Node2D

@onready var hud_menu = $HUD/M/HB/VB/Menu
@onready var console = $HUD/M/HB/ChatConsole
@onready var jc: JamConnect = $JamConnect

var the_api_key: String = ""

func _ready():
	console.jam_connect = jc
	hud_menu.get_popup().id_pressed.connect(_on_menu_selection)

#
# Server actions for player join/leave
#

func _on_jam_connect_player_connected(pid: int, username: String):
	$Level1.spawn_player(pid, username)

func _on_jam_connect_player_disconnected(pid: int, _username: String):
	$Level1.remove_player(pid)

#
# HUD interactions
#

func _on_console_pressed():
	console.visible = not console.visible

func _on_menu_selection(id: int):
	if id == 0:
		await jc.client.leave_game()
	elif id == 1:
		if await jc.client.leave_game():
			get_tree().quit(0)
		else:
			get_tree().quit(1)

#
# HUD controls for touchscreen
#

func _on_jam_connect_local_player_joining():
	$HUD.visible = true
	$HUD/TouchControl.visible = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

func _on_jam_connect_local_player_left():
	$Level1.reset()
	$HUD.visible = false
	$TitleZone/TitleCam.make_current()

func _on_jump_button_down():
	var e := InputEventAction.new()
	e.action = &"jump"
	e.pressed = true
	Input.parse_input_event(e)

func _on_jump_button_up():
	var e := InputEventAction.new()
	e.action = &"jump"
	e.pressed = false
	Input.parse_input_event(e)

func _on_right_button_down():
	Input.action_press(&"ui_right")

func _on_right_button_up():
	Input.action_release(&"ui_right")

func _on_left_button_down():
	Input.action_press(&"ui_left")

func _on_left_button_up():
	Input.action_release(&"ui_left")

# Example of fetching project variables in production after the server is in the "ready" state
func _on_jam_connect_server_post_ready():
	if jc.server.dev_mode:
		return
	var res = await jc.server.callback_api.get_vars(["THE_API_KEY"])
	if res.errored:
		printerr(res.error_msg)
		return
	print(res.data)
	print("fetched API key value: %s" % [res.data["vars"]["THE_API_KEY"]])
