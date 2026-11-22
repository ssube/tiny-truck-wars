# Changelog

## 0.2.0

- Runs much faster: about twice the frame rate in a big battle and four times
  or more in a normal skirmish. The ground is shaded once per world pixel,
  only changed ground is sent to the graphics card, and debris out of view
  is not drawn.
- The picture is enlarged by whole factors only, so pixels stay square and
  sharp, and every screen size starts on about the same view of the map.
- A title screen: any of the three maps, the saved game, or the Mud Lab.
- The mouse wheel zooms one step per notch, toward the cursor.
- The Mud Lab's camera follows the vehicle you drive.
- Fixed: a game crashed when a selected structure was destroyed.
- Fixed: the R (lay road) and F (special) keys did nothing.
- Routes keep clear of buildings, trees and wrecks, prefer roads, keep out
  of water, and go round vehicles standing in the way.
- Units no longer drive through each other, and shells are drawn as tracers.

## 0.1.0

The first release.

- The ground: mud, grass, gravel, sand and pavement that rut, wear and slump;
  craters; water that runs, pools in ruts and soaks the ground; snow, oil,
  fire, wind and rain; trees that fall into logs and buildings that collapse.
- Vehicles slowed and worn by what they drive on, getting stuck, stalling,
  flooding, and being winched out and towed home.
- The RTS: garages, fuel depots (that cluster and chain-explode) and helipads;
  tanks with ballistic shells that lead their targets; helicopters in the
  wind; the Wrecker, Tanker, Engineer and Water tanker kits; the bucket
  helicopter; the boss, the hippy and the nurse.
- A computer opponent, three skirmish maps (River crossing, Snowfield, Dunes),
  saving and loading, and a menu.
