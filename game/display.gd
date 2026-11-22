extends Node
## Whole-number scaling of the picture (the autoload TtwDisplay). The layout is
## made for LAYOUT pixels and is enlarged by the largest whole factor at which
## that still fits the window: 1 up to 2559×1439, 2 from 2560×1440, 3 from
## 3840×2160. So a world pixel always covers a whole number of screen pixels
## at a whole camera zoom, and the terrain's buffer goes on screen in equal
## square blocks.
##
## The project's stretch settings (canvas_items, expand, integer) round the
## factor down by themselves, but leave what the rounding frees as black bars:
## at 1920×1080 a 1280×720 picture in the middle. The layout's size is set
## here to the window's size over the factor, so the view fills the window
## (1920×1080 at factor 1) and only the remainder of the division is margin.

const LAYOUT := Vector2i(1280, 720)

func _ready() -> void:
	get_window().size_changed.connect(fit)
	fit()

## The whole factor a window of `size` px is enlarged by.
static func factor_for(size: Vector2i) -> int:
	return maxi(1, mini(size.x / LAYOUT.x, size.y / LAYOUT.y))

func fit() -> void:
	var window := get_window()
	var wanted := window.size / factor_for(window.size)
	if window.content_scale_size != wanted:
		window.content_scale_size = wanted
