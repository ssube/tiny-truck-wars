# Art

Every unit and structure has a PixelLab sprite (8 directions, low top-down),
fetched into the ignored `import_dump/` with `tools/pixellab_download.py --ids`
(characters need `--characters`). Art still to make gets a prompt here, written
to match these: one vehicle, front three-quarter view, faded paint with a few
bold patches of wear, dark outlines, broad pixel clusters.

## Made

| Unit | Kind | Size | Id |
|---|---|---|---|
| Truck (Soviet 10-ton 6×6) | character | 48 | dbf0e54e-5929-4d80-9dc4-0370afae982d |
| Tank (T-34) | character | 64 | 8835f4c4-7448-4a9c-932f-4dcbc17d2f06 |
| Hippy (battered Lada, smoke animation) | character | 48 | ab8f3c41-f5a8-474b-a658-5fdf2671b6e1 |
| Helicopter (Mi-24) | character | 56 | fa77e562-fe24-4f4f-ab38-ee44d4587152 |
| Boss (black state limousine) | character | 56 | d14e4b58-4e3a-4cf0-a5e2-d27403a8492b |
| Nurse (UAZ-452 field ambulance) | character | 48 | e2a60da7-90aa-40f0-86d2-efe80e937801 |
| Wrecker (the truck as a tow truck: state `as_a_tow_truck`) | character | 48 | a86ec024-6a64-45af-ae88-755a9dbe9608 |
| Garage | object | 68 | 013cc06a-530f-4b65-960f-833f8c2149f8 |
| Fuel depot | object | 68 | ef9e255e-2cd4-401e-9004-db3b372e38c2 |
| Helipad | object | 68 | cf233dc2-4998-451c-9159-87e1f6dde041 |

## Soviet Army

The side that is made (above), with the prompts it was made from.

### Soviet Army 10-ton 6×6 cargo truck

> A hulking Soviet Army 10-ton 6×6 cargo truck in crisp pixel art, shown in a slightly elevated front three-quarter view. A long squared hood, flat split windshield, heavy steel bumper, round headlights, and three axles with chunky black tires. The long cargo bed sits under a faded khaki canvas cover with a squared-off rear and broad folds. Faded olive-drab paint, a small red star on the cab door, and dried mud along the wheel arches. Bold silhouette, dark outlines, a muted palette, and large, deliberate pixel clusters that read at sprite scale. Full vehicle centered on a transparent background.

### T-34 tank

> A Soviet T-34 tank in crisp pixel art, shown from a slightly elevated front three-quarter view. Low hull with sharply sloped armor, a compact rounded turret, and a straight gun barrel aimed forward. Wide steel tracks wrap around five large road wheels on each side. Faded olive-green paint, a small red star on the turret, chipped armor edges, and dried mud packed into the tracks. Bold silhouette, dark outlines, and broad pixel clusters that keep the turret, hull, and tracks distinct at sprite scale. Full tank centered on a transparent background.

### Beat-up Lada

> A cheap, battered Soviet Lada sedan in crisp pixel art, seen from a slightly elevated front three-quarter view. Boxy body, faded mustard-yellow paint, a mismatched pale-blue front fender, rust along the rocker panels, and one missing hubcap. Keep the damage in a few bold patches so the car reads at sprite scale. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

### Black Soviet limousine

> A long black Soviet state limousine in crisp pixel art, seen from a slightly elevated front three-quarter view. Stretched passenger cabin, long flat hood, broad chrome grille, dark windows, and a tiny red pennant on one front fender. Use charcoal panels and clean steel-gray highlights to show the polished black body. Formal, heavy silhouette, dark outlines, full vehicle centered on a transparent background.

### UAZ-452 ambulance

> A Soviet UAZ-452 field ambulance in crisp pixel art, seen from a slightly elevated front three-quarter view. Short, rounded van body with a blunt cab-over nose, two round headlights, a split windshield, and chunky tires. Faded olive-green paint, a bold red cross on a white square on the side, and a few broad patches of dried mud along the lower body. Keep the rounded roof and stubby nose readable at sprite scale. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

### Army motor-pool garage

> A low Soviet Army vehicle garage in crisp pixel art, seen from a slightly elevated front three-quarter view. Rough concrete walls, a shallow corrugated roof, and two wide olive-green service bays. One bay is rolled up to reveal a dark interior. A small red star over the doors, a narrow strip of high windows, and a cracked concrete apron. Bold rectangular forms, muted concrete gray and olive drab, full building centered on a transparent background.

### Army fuel depot

> A compact Soviet Army fuel depot in crisp pixel art, seen from a slightly elevated front three-quarter view. Two large horizontal olive-drab fuel tanks on low concrete cradles, a squat pump shed, and a short row of rusty drums. Broad faded cream bands break up the tanks, with a small red star on the shed and a dark fuel stain on the concrete pad. Keep the tanks and shed distinct at sprite scale. Dark outlines, broad pixel clusters, full depot centered on a transparent background.

### Mi-24 Hind helicopter

> A Soviet Mi-24 Hind helicopter in crisp pixel art, seen from a slightly elevated front three-quarter view. Bulky armored fuselage, rounded tandem cockpit with two stepped glass canopies, short downward-sloping stub wings, and a long tapering tail boom. Show the main rotor as crisp, distinct blades. Faded olive-and-tan camouflage in broad patches, dark blue-gray cockpit glass, and a small red star on the flank. Strong silhouette, full helicopter centered on a transparent background with room for the rotor and tail.

### Soviet Army helipad

> A compact Soviet Army helipad in crisp pixel art, seen from a slightly elevated front three-quarter view. A square slab of weathered concrete with a wide, faded white landing circle and a bold block H in the center. Four squat amber lights mark the corners, and a chipped olive-drab equipment box with a small red star sits just off the back edge. Use dark outlines, broad pixel clusters, and a muted gray-and-olive palette to match the motor pool. Keep the landing surface clear. Full pad centered on a transparent background.

### Still to make: the truck kits and the bucket helicopter

Today the wrecker, tanker, engineer and water tanker all use the cargo
truck, and the bucket helicopter uses the Mi-24. The wrecker and the tanker
are trucks of their own, with their own cab and shape, so they are told
apart from everything else at a glance: the wrecker a bigger, heavier
truck, the tanker a smaller, rounder one. The engineer and the water tanker
keep the cargo truck's chassis, cab and paint with the bed swapped.
Character, 48, like the truck (the wrecker can go to 56).

#### Wrecker (KrAZ-255)

> A massive Soviet KrAZ-255 6×6 recovery truck in crisp pixel art, seen from a slightly elevated front three-quarter view. A tall, wide, rounded hood with a broad vertical-slatted grille, a high boxy cab with a flat windshield, and three axles on huge single balloon tires, bigger than any cargo truck's. The open steel deck behind the cab carries a heavy crane boom folded back over it with a big hook, a cable drum behind the cab, and a thick towing hitch and spade at the rear. Faded olive-drab paint, a small red star on the cab door, yellow-and-black hazard stripes on the boom tip, and dried mud caked on the big tires. Keep the huge tires, the tall hood, and the boom bold enough to read at sprite scale. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

#### Fuel tanker (ZIL-131)

> A Soviet ZIL-131 fuel tanker truck in crisp pixel art, seen from a slightly elevated front three-quarter view. A compact truck, shorter and lower than a 10-ton cargo truck: a short sloping hood with a wide flat grille, rounded front fenders, a small two-seat cab, and three axles with chunky tires. A fat rounded oval fuel tank fills the bed, with a hatch and walkway on top and a coiled black hose and pump box at the rear. Faded olive-drab paint, a broad faded cream band around the tank like the fuel depot's, a small red star on the cab door, and a dark fuel stain under the hose. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

#### Engineer road truck

> A Soviet Army 6×6 combat engineer truck in crisp pixel art, seen from a slightly elevated front three-quarter view. The same long squared hood, flat split windshield, round headlights, and three axles with chunky black tires as a Soviet 10-ton cargo truck, with a wide steel dozer blade mounted on the front bumper and an open tipper bed heaped with gray gravel. A shovel and a pick are strapped to the bed's side. Faded olive-drab paint, a small red star on the cab door, a scraped silver edge on the blade, and dried mud along the wheel arches. Keep the blade and the gravel heap bold so the truck reads as a road builder at sprite scale. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

#### Water tanker

> A Soviet Army 6×6 water tanker truck in crisp pixel art, seen from a slightly elevated front three-quarter view. The same long squared hood, flat split windshield, round headlights, and three axles with chunky black tires as a Soviet 10-ton cargo truck, with a squared-off water tank on the bed, a thick suction hose coiled along its side, and a spray nozzle on a short swivel mount at the rear. Faded olive-drab paint with a broad pale-blue band around the tank so it never reads as the fuel tanker, a small red star on the cab door, and wet streaks down the tank. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

#### Bucket helicopter (Mi-8)

> A Soviet Mi-8 transport helicopter in crisp pixel art, seen from a slightly elevated front three-quarter view, with a firefighting water bucket hanging below it. Long rounded fuselage, a big glazed nose, a square side door, and a tapering tail boom. Show the five-blade main rotor as crisp, distinct blades. A short cable drops from the belly to an orange collapsible bucket, slightly dripping. Faded olive-and-tan camouflage in broad patches, dark blue-gray glass, and a small red star on the flank. Strong silhouette, full helicopter and bucket centered on a transparent background with room for the rotor and tail.

## U.S. Army

The second side, not yet made.

### U.S. Army 10-ton cargo truck

> A hulking Cold War U.S. Army 10-ton 6×6 cargo truck in crisp pixel art, seen from a slightly elevated front three-quarter view. Tall upright grille, broad rounded fenders, split windshield, heavy bumper, and three axles with chunky tires. A faded tan canvas cover stretches over the long cargo bed. Olive-drab body, a stenciled white star on the door, and dry mud around the wheels. Dark outlines, broad pixel clusters, full truck centered on a transparent background.

### M4 Sherman tank

> A U.S. Army M4 Sherman tank in crisp pixel art, seen from a slightly elevated front three-quarter view. Tall hull, rounded cast turret, short straight gun barrel, and steel tracks with paired road wheels. Faded olive-drab armor, a bold white star on the hull side, and a few spare track links strapped across the nose. Use broad highlights to pick out the turret and dark pixel clusters to separate the tracks from the hull. Full tank centered on a transparent background.

### Beat-up Ford Pinto

> A cheap, battered 1970s Ford Pinto hatchback in crisp pixel art, seen from a slightly elevated front three-quarter view. Short rounded nose, sloping rear hatch, skinny tires, and faded burnt-orange paint. One mismatched primer-gray door, a missing hubcap, and a few chunky rust patches along the bottom edge. Dark outlines, clear pixel clusters, full car centered on a transparent background.

### Black Cadillac limousine

> A long black 1970s Cadillac Fleetwood limousine in crisp pixel art, seen from a slightly elevated front three-quarter view. Long flat hood, wide chrome grille, squared headlights, stretched passenger cabin, and a black vinyl roof. Thin whitewall tires and a tiny American fender flag. Use broad charcoal panels and a few sharp chrome highlights to define the glossy body. Full limousine centered on a transparent background.

### M725 ambulance

> A U.S. Army M725 field ambulance in crisp pixel art, seen from a slightly elevated front three-quarter view. Long square hood, upright grille, broad front fenders, and a tall rectangular patient compartment behind the cab. Faded olive-drab paint, a bold red cross on a white square on the side, and a small white star on the cab door. Use broad highlights to define the hood and the raised box body. Dark outlines, broad pixel clusters, full vehicle centered on a transparent background.

### Army motor-pool garage

> A U.S. Army motor-pool garage in crisp pixel art, seen from a slightly elevated front three-quarter view. Low tan cinder-block walls, a ribbed olive-green metal roof, and two wide roll-up service bays. One door is raised over a dark interior. A white star on a green sign and faded yellow stripes on the concrete apron tie it to the U.S. Army vehicles. Bold rectangular shapes, dark outlines, full building centered on a transparent background.

### Army fuel depot

> A compact U.S. Army fuel depot in crisp pixel art, seen from a slightly elevated front three-quarter view. Two horizontal sand-colored fuel tanks with dark steel bands, a squat olive-green pump shed, and a short row of red-brown drums. A chipped yellow curb borders the stained concrete pad. Keep the tanks, shed, and drums readable as separate shapes at sprite scale. Full depot centered on a transparent background.

### AH-1 Cobra helicopter

> A U.S. Army AH-1 Cobra helicopter in crisp pixel art, seen from a slightly elevated front three-quarter view. Slim fuselage, pointed nose, narrow stepped tandem canopy, short stub wings, and a long tail boom. Show the two-blade main rotor as crisp, distinct shapes. Faded olive-drab paint, dark blue-gray cockpit glass, and a small white U.S. Army marking on the flank. Full helicopter centered on a transparent background with room for the rotor and tail.

### Army helipad

> A compact U.S. Army helipad in crisp pixel art, seen from a slightly elevated front three-quarter view. A square concrete pad with a bold white H, a weathered yellow perimeter stripe, and four squat amber corner lights. An olive-green equipment cabinet and a small orange windsock sit behind the pad, leaving the landing surface clear. Broad pixel clusters, muted concrete gray and olive drab, full pad centered on a transparent background.

### Still to make: the truck kits and the bucket helicopter

As on the Soviet side: the wrecker (a bigger truck) and the tanker (a
smaller one) are trucks of their own; the engineer and the water tanker keep
the cargo truck's cab, chassis and paint with the bed swapped.

#### Wrecker (M816)

> A Cold War U.S. Army M816 5-ton 6×6 wrecker in crisp pixel art, seen from a slightly elevated front three-quarter view. A blunt, flat-faced hood with a wide mesh grille, squared flat fenders, a square open-topped cab with a canvas roof, and three axles with big dual rear tires. A heavy rotating crane with a long boom and a big hook sits on the bed, with a cable winch behind the cab, outrigger legs folded at the sides, and a tow bar at the rear. Olive-drab body, a stenciled white star on the door, yellow-and-black hazard stripes on the boom, and dry mud around the wheels. Keep the boom and winch bold enough to read at sprite scale. Dark outlines, broad pixel clusters, full truck centered on a transparent background.

#### Fuel tanker (M49)

> A U.S. Army M49 2½-ton fuel tanker, the "deuce and a half", in crisp pixel art, seen from a slightly elevated front three-quarter view. A smaller, narrower truck than the 10-ton cargo truck: a short hood with a vertical-bar grille, rounded swept front fenders, a small cab with a canvas roof, and three axles with chunky tires. A sand-colored, square-ended fuel tank fills the bed, bound by dark steel bands like the depot's tanks, with a top walkway and a reel of black hose at the rear. Olive-drab cab, a stenciled white star on the door, a red "FLAMMABLE" placard as a few bold pixels, and a dark fuel stain under the hose. Dark outlines, broad pixel clusters, full truck centered on a transparent background.

#### Engineer road truck

> A Cold War U.S. Army 6×6 engineer dump truck in crisp pixel art, seen from a slightly elevated front three-quarter view. The same tall upright grille, broad rounded fenders, split windshield, and three axles with chunky tires as a U.S. Army 10-ton cargo truck, with a wide steel dozer blade on the front bumper and an open dump bed heaped with gray gravel. A shovel and a pick are strapped to the bed's side, and a small yellow engineer castle sign is on the bumper. Olive-drab body, a stenciled white star on the door, a scraped silver edge on the blade, and dry mud around the wheels. Dark outlines, broad pixel clusters, full truck centered on a transparent background.

#### Water tanker

> A Cold War U.S. Army 6×6 water tanker truck in crisp pixel art, seen from a slightly elevated front three-quarter view. The same tall upright grille, broad rounded fenders, split windshield, and three axles with chunky tires as a U.S. Army 10-ton cargo truck, with a squared-off water tank on the bed painted with a broad pale-blue band, a thick suction hose coiled along its side, and a spray nozzle on a short swivel mount at the rear. Olive-drab body, a stenciled white star on the door, a white "WATER" stencil as a few bold pixels, and wet streaks down the tank. Dark outlines, broad pixel clusters, full truck centered on a transparent background.

#### Bucket helicopter (UH-1 Huey)

> A U.S. Army UH-1 Huey helicopter in crisp pixel art, seen from a slightly elevated front three-quarter view, with a firefighting water bucket hanging below it. Rounded nose with a wide windshield, an open side cabin door, landing skids, and a slim tail boom. Show the two-blade main rotor as long, crisp, distinct shapes. A short cable drops from the belly to an orange collapsible bucket, slightly dripping. Faded olive-drab paint, dark blue-gray glass, and a small white U.S. Army marking on the tail boom. Strong silhouette, full helicopter and bucket centered on a transparent background with room for the rotor and tail.

## The world (both sides)

Trees, logs, buildings and rubble are placeholders drawn by
`tools/make_world_textures.py`. They are drawn once, not turned, so each is
a single view (object, 1 direction) seen from the same slightly elevated
angle as the units, with its base at the bottom of the image. The sizes are
the placeholders' (width × height in pixels); the game reads the tree trunk
and building footprint from them (`prefabs/world/`), so a new sprite of a
different size needs its prefab's footprint checked. Neither army's colours
or markings: rural Eastern European countryside that suits both.

### Oak tree (two of them), 40 × 56

> A broad leafy oak tree in crisp pixel art, seen from a slightly elevated front view. A thick, slightly crooked brown trunk with a short root flare, and a big rounded crown of dark and mid greens in a few chunky lobes, lit from the top left. Dark outlines, broad pixel clusters, and a muted palette that sits on grass and mud without blending in. The trunk's base sits at the bottom center. Full tree on a transparent background.

> A second, smaller leafy oak tree in crisp pixel art, seen from a slightly elevated front view. A thinner trunk leaning slightly, and a lopsided crown of two or three rounded clumps of dark and mid green with a gap of sky between them, lit from the top left. Dark outlines, broad pixel clusters, muted palette. The trunk's base sits at the bottom center. Full tree on a transparent background.

### Pine tree, 40 × 56

> A tall dark pine tree in crisp pixel art, seen from a slightly elevated front view. A narrow straight brown trunk showing at the bottom, and four or five stacked triangular tiers of deep blue-green needles that widen toward the base, each tier edged with a lighter highlight on the top left. Dark outlines, broad pixel clusters, muted palette that reads on both snow and grass. The trunk's base sits at the bottom center. Full tree on a transparent background.

### Fallen log, 48 × 10

> A fallen tree trunk lying on its side in crisp pixel art, seen from a slightly elevated view, running left to right. Rough brown bark in chunky strips, a pale round cut face with rings at the right end, a splintered torn end at the left, and two snapped-off branch stubs. Dark outlines, broad pixel clusters, muted palette. Full log on a transparent background.

### Stump, 12 × 9

> A small tree stump in crisp pixel art, seen from a slightly elevated view. A short brown bark ring with a jagged, splintered pale top where the tree snapped off, and a little root flare at the base. Dark outlines, very few colors so it reads at a tiny size. Full stump on a transparent background.

### Farmhouse, 56 × 44

> A small rural Eastern European farmhouse in crisp pixel art, seen from a slightly elevated front view. Whitewashed plaster walls with a few bare patches of brick, a steep red-brown tiled roof, a short brick chimney, a plain wooden door in the middle, and four small square windows with blue-painted frames. Muted colors, dark outlines, broad pixel clusters, bold rectangular shapes. Full building on a transparent background.

### Wooden shed, 40 × 32

> A small weathered wooden farm shed in crisp pixel art, seen from a slightly elevated front view. Gray-brown vertical plank walls, a sagging corrugated tin roof with rust streaks, a single plank door hanging slightly askew, and a woodpile stacked against one side. Muted colors, dark outlines, broad pixel clusters. Full building on a transparent background.

### Barracks, 76 × 48

> A long single-storey military barracks in crisp pixel art, seen from a slightly elevated front view. Pale gray-green painted wooden walls, a low pitched roof of dark tar paper, a row of six evenly spaced small windows, a central door under a short porch roof, and a stovepipe on the roof. No flags or national markings. Muted colors, dark outlines, broad pixel clusters, bold horizontal shapes. Full building on a transparent background.

### Rubble, 56 × 32

> A low heap of building rubble in crisp pixel art, seen from a slightly elevated view. Broken chunks of whitewashed plaster and red brick, a few charred and snapped roof beams sticking out at angles, scattered roof tiles, and gray dust around the edges. Low and wide, no taller than a third of its width. Muted colors with a few dark scorch patches, dark outlines, broad pixel clusters. Full heap on a transparent background.

## Effects

The thrown bits are tiny sheets drawn by `tools/make_fx_textures.py`: one
row of frames, each frame a variant the particles pick from. They are 6 px
frames (dust 16 px), below what PixelLab draws, so make them at 16 px and
scale them down, or keep them as they are; at that size they read as
specks either way.

> A sprite sheet of four small clumps of wet brown mud in crisp pixel art, each a different blobby shape, with a darker underside and a single lighter wet highlight. Very few colors, dark outlines, on a transparent background.

> A sprite sheet of four small pieces of wreckage in crisp pixel art: a bent steel plate, a short twisted bar, a broken bolt-and-bracket, and a dark charred fragment, in gray and olive drab. Very few colors, dark outlines, on a transparent background.

> A sprite sheet of four small water droplets and splashes in crisp pixel art, pale blue-white with a single bright highlight, from a round drop to a flattened splat. Very few colors, on a transparent background.

> A sprite sheet of six soft puffs of tan dust in crisp pixel art, growing from a small tight puff to a wide thin wisp, lighter at the top and fading at the edges. Few colors, no outlines, on a transparent background.
