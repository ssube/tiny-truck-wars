class_name TtwMatch extends Component
## A skirmish on the map's entity: the sides in play and how it ended
## (TtwMatchSystem). A side with no garage left has lost.

var teams: PackedInt32Array = PackedInt32Array([1, 2])
var winner: int = -1
var over: bool = false
