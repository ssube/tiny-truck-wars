class_name TtwSpray extends RefCounted
## Water poured on the map (a tanker's spray, a bucket's drop): the volume
## goes into the water, the ground under it is soaked (mud on purpose),
## fires under it go out, and it splashes.

## Pours `volume` on a disc of `radius_px` at `at`. Returns what landed.
static func pour(session: KitSession, fx: TtwFx, at: Vector2, volume: float, radius_px: float) -> float:
	var terrain := TtwGround.of(session)
	var water := TtwGround.water_of(session)
	if terrain == null or water == null or volume <= 0.0:
		return 0.0
	var landed := water.pour(at, volume, radius_px)
	var field := TtwGround.fire_of(session)
	if field != null:
		var lo := terrain.tile_of(at - Vector2(radius_px, radius_px))
		var hi := terrain.tile_of(at + Vector2(radius_px, radius_px))
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				field.douse(Vector2i(x, y))
	if fx != null:
		fx.water.splash(at, radius_px, 0.6, 0.1, 2.0)
		fx.debris.throw(TtwDebris.Kind.DROPLET, Vector3(at.x, at.y, 8.0), Vector2.RIGHT, radius_px * 1.5, TAU, 30.0, clampi(int(volume * 2.0), 4, 30))
	return landed
