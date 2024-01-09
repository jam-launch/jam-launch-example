@tool
extends VBoxContainer

@onready var title: Label = $TopBar/Title
@onready var err_label: Label = $ErrMsg
@onready var deployment: VBoxContainer = $M/VB/Deployment

@onready var net_mode_box: OptionButton = $M/VB/HB/HB/NetworkMode

signal request_projects_update()
signal go_back()

var project_data = []
var project_api: ProjectApi

var refresh_retries = 0

var active_project
var active_id = ""
var error_msg = null :
	set(value):
		if value == null:
			err_label.visible = false
		else:
			err_label.text = value
			err_label.visible = true

func _dashboard():
	return get_parent()

func _plugin() -> EditorPlugin:
	return _dashboard().plugin

func initialize():
	project_api = _dashboard().project_api

func show_project(project_id: String, project_name: String = "..."):
	active_id = project_id
	$TopBar/BtnBack.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Back", "EditorIcons")
	$TopBar/BtnRefresh.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Reload", "EditorIcons")
	$M/VB/BtnDeploy.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("ArrowUp", "EditorIcons")
	title.text = project_name
	refresh_project()

func refresh_project() -> bool:
	$AutoRefreshTimer.stop()
	
	net_mode_box.disabled = true
	$TopBar/BtnRefresh.disabled = true
	var res = await project_api.get_project(active_id)
	$TopBar/BtnRefresh.disabled = false
	net_mode_box.disabled = false
	if res.errored:
		error_msg = res.error_msg
		return false
	setup_project_data(res.data)
	return true

func setup_project_data(p):
	while deployment.get_child_count() > 0:
		deployment.remove_child(deployment.get_child(0))
	
	active_project = p
	title.text = p["project_name"]
	
	var net_mode = active_project["configs"][0]["network_mode"]
	net_mode_box.disabled = false
	if net_mode == "enet":
		net_mode_box.select(0)
	elif net_mode == "websocket":
		net_mode_box.select(1)
	else:
		net_mode_box.select(-1)
	
	if "releases" in active_project and len(active_project["releases"]) > 0:
		$M/VB/DeploymentsLabel.text = ""
		var r = active_project["releases"][len(active_project["releases"]) - 1]
		
		var l = Label.new()
		l.text = "Latest Release - %s" % r["release_id"]
		deployment.add_child(l)
		
		l = Label.new()
		var rt = Time.get_datetime_dict_from_datetime_string(r["start_time"], false)
		l.text = "%s-%s-%s %s:%s" % [
			rt["year"],
			rt["month"],
			rt["day"],
			rt["hour"],
			rt["minute"],
		]
		deployment.add_child(l)
		
		var plab = Label.new()
		var pbtn = Button.new()
		var phb = HBoxContainer.new()
		phb.add_child(plab)
		phb.add_child(pbtn)
		deployment.add_child(phb)
		if r["public"]:
			plab.text = "Release is Public"
			pbtn.text = "Make Private"
			pbtn.pressed.connect(_update_release.bind(pbtn, p["id"], r["release_id"], {"public": false}))
		else:
			plab.text = "Release is Private"
			pbtn.text = "Make Public"
			pbtn.pressed.connect(_update_release.bind(pbtn, p["id"], r["release_id"], {"public": true}))
		
		var btn = Button.new()
		btn.text = "Download Link"
		var download_link = "https://app.jamlaunch.com/g/%s/%s" % [p["id"], r["release_id"]]
		btn.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("ActionCopy", "EditorIcons")
		btn.pressed.connect((func(url): DisplayServer.clipboard_set(url)).bind(download_link))
		deployment.add_child(btn)
		
		for j in r["jobs"]:
			var n = Label.new()
			n.text = "%s: %s" % [j["job_name"], j.get("status")]
			deployment.add_child(n)
			if j.get("status") not in ["SUCCEEDED", "FAILED"]:
				$AutoRefreshTimer.start(3.0)
				
				
		if r["game_id"] != null:
			var dir = self.get_script().get_path().get_base_dir()
			var deployment_cfg = ConfigFile.new()
			deployment_cfg.set_value("game", "id", r["game_id"])
			var err = deployment_cfg.save(dir + "/../deployment.cfg")
			if err != OK:
				error_msg = "Failed to save current deployment configuration"
				return
	else:
		$M/VB/DeploymentsLabel.text = "No active deployments..."

func _update_release(btn: BaseButton, project_id: String, release_id: String, props: Dictionary):
	btn.disabled = true
	var res = await project_api.update_release(project_id, release_id, props)
	btn.disabled = false
	if res.errored:
		error_msg = res.error_msg
		return
	refresh_project()

func _on_btn_upload_pressed() -> void:
	error_msg = null

func _on_btn_deploy_pressed() -> void:
	error_msg = null
	net_mode_box.disabled = true
	$M/VB/BtnDeploy.disabled = true
	var project_dir = _plugin().get_editor_interface().get_resource_filesystem().get_filesystem()
	var res = await project_api.build_project(active_id, project_dir)
	net_mode_box.disabled = false
	$M/VB/BtnDeploy.disabled = false
	if res.errored:
		error_msg = res.error_msg
		return
	refresh_retries = 2
	$AutoRefreshTimer.start(4.0)

func _on_btn_refresh_pressed() -> void:
	error_msg = null
	refresh_project()

func _on_btn_back_pressed() -> void:
	go_back.emit()

func _on_log_out_btn_pressed() -> void:
	_dashboard().jwt().clear()

func _on_auto_refresh_timer_timeout():
	$AutoRefreshTimer.stop()
	await refresh_project()
	if $AutoRefreshTimer.is_stopped():
		if refresh_retries > 0:
			refresh_retries -= 1
			$AutoRefreshTimer.start(3.0)
	else:
		refresh_retries = 0

func _on_btn_delete_pressed():
	$ConfirmDelete.popup()

func _on_confirm_delete_confirmed():
	var res = await project_api.delete_project(active_id)
	if res.errored:
		error_msg = res.error_msg
		return
	go_back.emit()

func _on_option_button_item_selected(index):
	
	if not active_project:
		return
	
	var cfg = {}
	if index == 0:
		cfg["network_mode"] = "enet"
	elif index == 1:
		cfg["network_mode"] = "websocket"
	else:
		return
	
	$M/VB/BtnDeploy.disabled = true
	net_mode_box.disabled = true
	var res = await project_api.post_config(active_id, cfg)
	net_mode_box.disabled = false
	$M/VB/BtnDeploy.disabled = false
	
	if res.errored:
		error_msg = res.error_msg
		return
