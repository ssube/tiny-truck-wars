extends Node
## Store screenshots at 1920x1080 (reports/itch/shot-*.png): a battle at the
## river, a column in the snow, helicopters over the dunes, the mud and water
## at work, a depot chain going up. Vehicles drive laps first (`_laps`), so
## the ground shows the ruts and tracks of a game under way. For the itch.io page, looked at, not
## compared. Run at 1080p:
## Zooms are for a 1920×1080 window (whole-factor scaling, factor 1): zoom 3
## is 3 screen px per world px.
##   xvfb-run -a -s '-screen 0 1920x1080x24' godot --path . --audio-driver Dummy \
##     --resolution 1920x1080 res://tools/itch_shots.tscn

var problems: Array[String] = []
var game: TtwSkirmish
var tile := 16.0

func _ready() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Waits `count` game ticks (a slow renderer runs several a frame).
func _ticks(count: int) -> void:
	var until := game.session.tick + count
	while game.session.tick < until:
		await get_tree().process_frame

func _start(map: StringName) -> void:
	if game != null:
		game.queue_free()
		await get_tree().process_frame
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.map_name = map
	game.ai_teams = []
	add_child(game)
	await _frames(5)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/itch"))
	# ITCH_SHOTS=snow,mud renders only those.
	var only := OS.get_environment("ITCH_SHOTS").split(",", false)
	for shot in ["battle", "snow", "dunes", "mud", "chain"]:
		if only.is_empty() or only.has(shot):
			await call("_" + shot)
	print("ITCH_SHOTS: ", "PASS" if problems.is_empty() else str(problems))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)

## Drives `units` round the loop `points` for `ticks` game ticks, each from
## its own place on the loop, so the ground under them is worked as it is in
## a real game before the picture is taken.
func _laps(units: Array[Entity], points: PackedVector2Array, ticks: int) -> void:
	var leg := {}
	for k in units.size():
		leg[units[k]] = k % points.size()
		TtwPilotSystem.order(units[k], points[leg[units[k]]])
	var until := game.session.tick + ticks
	while game.session.tick < until:
		await get_tree().process_frame
		for unit in units:
			var body := game.session.body_of(unit)
			if body != null and body.global_position.distance_to(points[leg[unit]]) < 24.0:
				leg[unit] = (leg[unit] + 1) % points.size()
				TtwPilotSystem.order(unit, points[leg[unit]])

## Vehicles of one side drive `points` for `ticks` and are then taken off
## the map: the ground keeps what they did to it, and the scene is then set
## on it as it would stand after a while of play.
func _work_ground(kinds: Array, points: PackedVector2Array, ticks: int) -> void:
	var units: Array[Entity] = []
	for k in kinds.size():
		units.append(game.spawn_unit(kinds[k], points[k % points.size()] + Vector2(0, (k / points.size()) * 30), 0.0, 1))
	await _laps(units, points, ticks)
	for unit in units:
		game.session.retire(unit)
	await _frames(2)

## Two lines of tanks trading shells on the river's west bank, a gunship
## overhead, a nurse behind the line; a tank already burning and leaking oil,
## and fuel spilled into the river, its sheen carried downstream. The field
## has been driven over for a while first.
func _battle() -> void:
	await _start(&"river")
	var field := Vector2(38, 44) * tile
	await _work_ground([&"tank", &"tank", &"tanker", &"tank", &"wrecker", &"tank"], PackedVector2Array([field + Vector2(-160, -80), field + Vector2(70, -90), field + Vector2(80, 80), field + Vector2(-150, 85)]), 900)
	for k in 4:
		game.spawn_unit(&"tank", field + Vector2(-80, k * 28 - 42), 0.0, 1)
		game.spawn_unit(&"tank", field + Vector2(60, k * 28 - 42), PI, 2)
	game.spawn_unit(&"nurse", field + Vector2(-120, 10), 0.0, 1)
	game.spawn_unit(&"wrecker", field + Vector2(-130, -40), 0.0, 1)
	var heli := game.spawn_unit(&"gunship", field + Vector2(-50, -90), 0.0, 1)
	(heli.get_component(TtwFlight) as TtwFlight).altitude = 26.0
	# A wreck on the bank, bleeding oil, and a spill into the river.
	var bank := Vector2(TtwSkirmishMap.CHANNEL.x - 1, 42) * tile
	var wreck := game.spawn_unit(&"tank", bank, PI * 0.5, 2)
	TtwDamage.hurt(game.session, wreck, 1.0e6, bank + Vector2(-30, 0))
	var water := TtwGround.water_of(game.session)
	for k in 6:
		TtwOil.spill(game.terrain, water, bank + Vector2(16 + k * 4, k * 10), 6.0, 14.0)
	TtwOil.spill(game.terrain, water, bank + Vector2(-20, 20), 4.0, 18.0)
	game.commander.select_rect(Rect2(field - Vector2(150, 80), Vector2(110, 160)))
	game.camera.position = field + Vector2(40, -10)
	game.camera.zoom = Vector2(3, 3)
	await _ticks(220)
	await _shot("shot-1-battle")

## A column of trucks and tanks along the ploughed road through the snow,
## cutting tracks, snow still falling; two tanks have been out in the open
## snow beside it, their loops cut down to the ground.
func _snow() -> void:
	await _start(&"snowfield")
	var road := Vector2(12, 26) * tile
	var scouts: Array[Entity] = []
	for k in 2:
		scouts.append(game.spawn_unit(&"tank", Vector2(440 + k * 120, 250), 0.0, 1))
	await _laps(scouts, PackedVector2Array([Vector2(420, 240), Vector2(610, 270), Vector2(600, 500), Vector2(430, 480)]), 900)
	var kinds := [&"tank", &"tanker", &"tank", &"engineer", &"wrecker", &"tank"]
	for k in kinds.size():
		var unit := game.spawn_unit(kinds[k], road + Vector2(-k * 34, 18), 0.0, 1)
		TtwPilotSystem.order(unit, Vector2(30, 10) * tile)
	game.camera.position = Vector2(330, road.y - 40)
	game.camera.zoom = Vector2(3, 3)
	await _ticks(260)
	await _shot("shot-2-snow")

## Helicopters crossing the dunes in the wind, tanks at a gap in the ridge
## after a while out on the sand, dust off it.
func _dunes() -> void:
	await _start(&"dunes")
	var gap := Vector2(TtwDunesMap.RIDGE_X[0], TtwDunesMap.GAPS[1]) * tile
	var tanks: Array[Entity] = []
	for k in 3:
		tanks.append(game.spawn_unit(&"tank", gap + Vector2(-260 - k * 40, (k - 1) * 50), 0.0, 1))
	await _laps(tanks, PackedVector2Array([gap + Vector2(-320, -110), gap + Vector2(-90, -100), gap + Vector2(-80, 100), gap + Vector2(-310, 110)]), 900)
	for k in 3:
		TtwPilotSystem.order(tanks[k], gap + Vector2(160, (k - 1) * 20))
	for k in 2:
		var heli := game.spawn_unit(&"gunship" if k == 0 else &"bucket_heli", gap + Vector2(-60 + k * 70, -70 - k * 30), 0.0, 1)
		(heli.get_component(TtwFlight) as TtwFlight).altitude = 20.0
		TtwPilotSystem.order(heli, gap + Vector2(260, -40))
	game.camera.position = gap + Vector2(20, -20)
	game.camera.zoom = Vector2(3, 3)
	await _ticks(200)
	await _shot("shot-3-dunes")

## The mud and water at work: a wet field by the north ford churned by
## trucks and a tank going round it, water standing in the ruts, the tank
## bogged in them and a wrecker winching it out, a water tanker spraying.
func _mud() -> void:
	await _start(&"river")
	var field := Vector2(TtwSkirmishMap.CHANNEL.x - 12, TtwSkirmishMap.FORDS[0] + 3) * tile
	TtwBrushes.paint(game.terrain, TtwBrushes.Kind.WET, field, 90.0, 1.0)
	var churn: Array[Entity] = []
	for kind in [&"tank", &"tanker", &"engineer", &"tank"]:
		churn.append(game.spawn_unit(kind, field + Vector2(-100 + churn.size() * 40, -60), 0.0, 1))
	await _laps(churn, PackedVector2Array([field + Vector2(-110, -50), field + Vector2(90, -40), field + Vector2(100, 50), field + Vector2(-100, 45)]), 900)
	TtwBrushes.paint(game.terrain, TtwBrushes.Kind.WATER, field + Vector2(-10, 0), 30.0, 1.5, 0.0, TtwGround.water_of(game.session))
	var tank := churn[0]
	TtwPilotSystem.stop(tank)
	TtwBrushes.paint(game.terrain, TtwBrushes.Kind.DIG, game.session.body_of(tank).global_position, 14.0, 5.0)
	var wrecker := game.spawn_unit(&"wrecker", game.session.body_of(tank).global_position + Vector2(-70, 0), 0.0, 1)
	var sprayer := game.spawn_unit(&"water_tanker", field + Vector2(-40, 64), 0.0, 1)
	(sprayer.get_component(TtwWaterTank) as TtwWaterTank).amount = 8.0
	await _ticks(30)
	TtwWinchSystem.winch(game.session, wrecker, tank)
	TtwKitSystem.spray(sprayer, field + Vector2(40, 64))
	game.commander.select_at(game.session.body_of(wrecker).position)
	game.camera.position = field + Vector2(0, 10)
	game.camera.zoom = Vector2(4, 4)
	await _ticks(90)
	await _shot("shot-4-mud")

## A row of full depots: the first is hit and the rest go up after it.
func _chain() -> void:
	await _start(&"river")
	var row := Vector2(70, 46) * tile
	var depots: Array[Entity] = []
	for k in 4:
		depots.append(game.spawn_structure(&"depot", row + Vector2(k * 44, 0), 2))
		var d: TtwDepot = depots[k].get_component(TtwDepot)
		d.stock = d.capacity
	await _frames(5)
	game.camera.position = row + Vector2(66, -40)
	game.camera.zoom = Vector2(3, 3)
	TtwDamage.hurt(game.session, depots[0], 1.0e6, row - Vector2(30, 0))
	# Mid-chain: the second depot going up, the first one's fire and smoke.
	await _ticks(TtwDepotSystem.CHAIN_TICKS * 2 + 4)
	await _shot("shot-5-chain")

func _shot(name: String) -> void:
	game.camera.force_update_scroll()
	await get_tree().process_frame
	for i in 4:
		game.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != Vector2i(1920, 1080):
		problems.append("%s is %s, not 1920x1080" % [name, image.get_size()])
	var error := image.save_png(ProjectSettings.globalize_path("res://reports/itch/%s.png" % name))
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
