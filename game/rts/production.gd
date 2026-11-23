class_name TtwProduction extends RefCounted
## What things cost: units built at a garage or helipad (fuel and seconds),
## structures (fuel), and what a wreck broken up at a garage gives back. A
## unit kind is a chassis (`unit`, TtwUnits.SCENES) with a kit (TtwKits).

const UNITS := {
	&"tank": {"fuel": 120.0, "seconds": 12.0},
	&"wrecker": {"fuel": 60.0, "seconds": 8.0, "unit": &"truck", "kit": &"wrecker", "art": "wrecker", "beacon": true},
	&"tanker": {"fuel": 50.0, "seconds": 8.0, "unit": &"truck", "kit": &"tanker", "art": "tanker"},
	&"engineer": {"fuel": 70.0, "seconds": 9.0, "unit": &"truck", "kit": &"engineer"},
	&"water_tanker": {"fuel": 50.0, "seconds": 8.0, "unit": &"truck", "kit": &"water"},
	&"hippy": {"fuel": 40.0, "seconds": 6.0},
	&"boss": {"fuel": 150.0, "seconds": 15.0},
	&"nurse": {"fuel": 70.0, "seconds": 9.0},
	&"gunship": {"fuel": 140.0, "seconds": 14.0, "unit": &"helicopter", "kit": &"rockets"},
	&"bucket_heli": {"fuel": 110.0, "seconds": 12.0, "unit": &"helicopter", "kit": &"bucket"},
}
const STRUCTURES := {&"garage": 200.0, &"depot": 100.0, &"helipad": 120.0}
## Share of a unit's fuel cost a wreck of it gives back.
const SCRAP_SHARE := 0.3

static func unit_fuel(kind: StringName) -> float:
	return UNITS[kind].fuel if UNITS.has(kind) else 0.0

static func unit_seconds(kind: StringName) -> float:
	return UNITS[kind].seconds if UNITS.has(kind) else 0.0

## The chassis a kind is built on (itself if it is one).
static func chassis(kind: StringName) -> StringName:
	return UNITS[kind].get("unit", kind) if UNITS.has(kind) else kind

## The sprites a kind is drawn with (assets/units/<art>/), or "" for its
## chassis's own.
static func art(kind: StringName) -> String:
	return UNITS[kind].get("art", "") if UNITS.has(kind) else ""

## Whether a kind's sprite has a flashing beacon (TtwVehicle2D.beacon).
static func beacon(kind: StringName) -> bool:
	return UNITS[kind].get("beacon", false) if UNITS.has(kind) else false

## The kit a kind is fitted with (&"" for none).
static func kit(kind: StringName) -> StringName:
	return UNITS[kind].get("kit", &"") if UNITS.has(kind) else &""
