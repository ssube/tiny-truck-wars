class_name TtwFireAt extends Component
## An order to shell a spot on the ground (TtwGunSystem): out of range the
## unit closes in, in range it stops and fires at the spot each time it is
## loaded, until another order replaces this one.

## The spot (world px).
@export var at: Vector2 = Vector2.ZERO
