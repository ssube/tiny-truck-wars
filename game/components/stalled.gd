class_name TtwStalled extends Component
## The engine stalled under strain. It restarts by itself once `restart_ticks`
## run out, unless the vehicle is too worn to restart (TtwDriveSystem).

var restart_ticks: int = 0
