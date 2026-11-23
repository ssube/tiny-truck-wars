// A vehicle's flashing beacon: when it is lit, shared by its pixels on the
// sprite (vehicle.gdshader) and its light on the ground (beacon_glow), so
// the two flash together. Slow, like a real amber warning light: 48 flashes
// a minute, each held for 0.5 s, then dark; `phase` (0..1) keeps a group of
// them out of step.
const float BEACON_HZ = 0.8;
const float BEACON_ON = 0.4;

bool beacon_lit(float phase) {
	return fract(TIME * BEACON_HZ + phase) < BEACON_ON;
}
