class_name TtwKits extends RefCounted
## What each kit fits to its chassis (TtwProduction names the kit of a kind).

## Fresh components for `kit` (none for &"").
static func parts(kit: StringName) -> Array[Component]:
	var out: Array[Component] = []
	match kit:
		&"wrecker":
			out.append(TtwWinch.new())
		&"tanker":
			out.append(TtwTanker.new())
		&"engineer":
			out.append(TtwEngineer.new())
		&"water":
			out.append(TtwWaterTank.new())
		&"bucket":
			out.append(TtwBucket.new())
		&"rockets":
			var gun := TtwGun.new()
			gun.ammo = &"rocket"
			gun.range_tiles = 7.0
			gun.reload_seconds = 2.5
			gun.speed_tiles = 18.0
			gun.arc = 0.02
			gun.muzzle_px = 0.0
			gun.damage = 70.0
			gun.splash_tiles = 1.2
			gun.hits_air = false
			out.append(gun)
	return out
