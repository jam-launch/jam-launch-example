extends Node2D

var character_scn = preload("res://Character.tscn")

func spawn_player(pid: int, nametag: String):
	var p: CharacterBody2D = character_scn.instantiate()
	p.pid = pid
	p.nametag = nametag
	p.position = $SpawnPoints.get_children().pick_random().position
	p.name = str(pid)
	$Players.add_child(p, true)

func remove_player(pid):
	var p = $Players.get_node(str(pid))
	if p != null:
		p.queue_free()

func get_players():
	return $Players.get_children()

func reset():
	for p in $Players.get_children():
		p.queue_free()
