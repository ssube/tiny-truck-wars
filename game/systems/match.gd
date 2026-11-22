class_name TtwMatchSystem extends System
## Ends a skirmish (TtwMatch on the map's entity) when only one side still
## has a garage: that side wins.

signal match_over(winner: int)

var session: KitSession

func query() -> QueryBuilder:
	return q.with_all([TtwMatch])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var m: TtwMatch = entity.get_component(TtwMatch)
		if m.over:
			continue
		var standing := {}
		for garage in session.view([TtwGarage, TtwTeam]):
			var h: TtwHealth = garage.get_component(TtwHealth)
			if h == null or not h.destroyed:
				standing[TtwTeam.of(garage)] = true
		var left: Array = []
		for team in m.teams:
			if standing.has(team):
				left.append(team)
		if left.size() <= 1:
			m.over = true
			m.winner = left[0] if left.size() == 1 else -1
			session.notify("Side %d wins." % m.winner if m.winner >= 0 else "Nobody wins.")
			match_over.emit(m.winner)
