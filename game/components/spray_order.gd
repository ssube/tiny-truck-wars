class_name TtwSprayOrder extends Component
## Spray water on `target` (a Water tanker; TtwKitSystem): it drives within
## reach, then sprays until its tank is empty.

var target: Vector2
## It has been sent to get within reach (so arriving short of it ends the order).
var driving: bool = false
