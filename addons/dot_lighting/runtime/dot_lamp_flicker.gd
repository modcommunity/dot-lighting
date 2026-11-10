class_name DotLampFlicker
extends RefCounted

## A failing lamp: the brightness scale of a light at a moment, as a pure function of time, so a
## server and a client, or two runs, agree, and a suite can assert it.
##
## [codeblock]
## lamp.light_energy = base_energy * DotLampFlicker.scale(lamp_seed, time, 0.6)
## [/codeblock]
##
## It hums at a lamp's own pace (two sines at seed-dependent rates) and now and then drops almost
## out for a fraction of a second. [param amount] 0 is a steady lamp (always 1.0); 1 is a lamp that
## spends much of its time dim. Flashing is a comfort setting: pass [code]allow_flashes = false[/code]
## and the dropouts go, leaving only a slow, shallow drift.

## The dimmest a dropout gets, as a fraction of full.
const DROPOUT_FLOOR := 0.08

## Dropouts are decided in slots this long, in seconds.
const SLOT := 0.37

## The share of slots that drop out at amount 1.
const DROPOUT_RATE := 0.35


## A lamp's brightness scale, in [code][0, 1][/code], for a lamp with [param lamp_seed] at
## [param time] seconds.
static func scale(lamp_seed: int, time: float, amount: float, allow_flashes: bool = true) -> float:
	amount = clampf(amount, 0.0, 1.0)

	if amount <= 0.0:
		return 1.0

	var phase := float(posmod(lamp_seed * 7919, 1000)) * 0.013
	var rate := 1.7 + float(posmod(lamp_seed * 31, 17)) * 0.19
	var hum := 0.5 + 0.25 * sin(time * rate + phase) + 0.25 * sin(time * rate * 2.37 + phase * 1.9)

	if not allow_flashes:
		return clampf(1.0 - amount * 0.12 * (1.0 - hum), 0.0, 1.0)

	var result := 1.0 - amount * 0.35 * (1.0 - hum)
	var slot := int(floor(time / SLOT))

	if _hash01(lamp_seed, slot) < DROPOUT_RATE * amount:
		# Inside the slot the lamp dips and comes back: a dip, not a square pulse.
		var dip := sin((time / SLOT - float(slot)) * PI)
		result = lerpf(result, DROPOUT_FLOOR, clampf(dip * 2.0, 0.0, 1.0))

	return clampf(result, 0.0, 1.0)


## A stable number in [0, 1) from two integers.
static func _hash01(a: int, b: int) -> float:
	var h := ((a * 73856093) ^ (b * 19349663)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFF) / float(0x100000)
