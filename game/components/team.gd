class_name TtwTeam extends Component
## Whose side it is on: 0 neutral, 1 the player, 2 and up opponents.

const NEUTRAL := 0
const COLORS := [Color(0.75, 0.75, 0.7), Color(0.25, 0.55, 0.95), Color(0.9, 0.3, 0.25), Color(0.95, 0.8, 0.25)]

@export var team: int = 1

static func of(entity: Object) -> int:
	var t: TtwTeam = (entity as Entity).get_component(TtwTeam) if is_instance_valid(entity) else null
	return t.team if t != null else NEUTRAL

static func color(team: int) -> Color:
	return COLORS[clampi(team, 0, COLORS.size() - 1)]
