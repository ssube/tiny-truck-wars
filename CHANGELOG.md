# Changelog

## 0.2.4

- Fixed: water was drawn much too dark (0.2.2 and 0.2.3). The river is back
  to its colour, and a game saved in those versions loads with it too.

## 0.2.3

- Fixed: the game still would not start in some browsers (Chrome, Edge) and
  on some graphics cards, which count every texture a shader names. The
  ground now names 12, and every shader the game compiles is checked
  against 16 on each change.
- Building draws on your whole fuel supply: units, helicopters and
  structures are paid from all your depots together, wherever they are.
  Repairs and refuelling still use a depot near the garage or helipad.

## 0.2.2

- Fixed: the game would not start on graphics cards and browsers that give a
  shader only 16 textures. The ground now uses 16 at most, and a test keeps
  every shader within that.
- Ctrl and right click fires at a spot on the ground, a tree or a house.
- A wrecker can winch itself to a tree, log or house: out of the mud, or
  along.
- Who pushes whom goes by weight: tanks shove trucks and cars, trucks shove
  cars, and cars push nothing. Only a winch moves a wreck, and crashed
  helicopters are wrecks on the ground too.
- Water can have its own colour: the snowfield's lake is icy blue, the dune
  oasis green.
- Fixed: S did not scroll down. Stop is now H.
- Fixed: reflections showed over dry ground beside the water.
- The water's maps go to the graphics card only when the water changes.

## 0.2.1

- Fixed: flames were drawn upside down, with the bright core at the top and
  the torn tips hanging below. They now burn upright from the ground.

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
