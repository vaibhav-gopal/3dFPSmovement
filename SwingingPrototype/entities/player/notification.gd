extends Panel

export var sizeOfPanel = Vector2(220, 85)
export var margins = Vector2(50,25)

onready var tween = $notificationTween
onready var label = $VBoxContainer/notificationLabel
onready var title = $VBoxContainer/notificationTitle

var targetPosition
var startPosition

var running
var initial = false

func _ready():
	rect_min_size = sizeOfPanel
	hide()

func _show_notif(titleString: String, labelString: String, time: float, delay: float, type):
	if tween.is_active() and type == running:
		if !initial && tween.tell() < time:
			tween.seek(0)
		title.text = titleString
		label.text = labelString
	else:
		targetPosition = Vector2(get_viewport_rect().size.x - sizeOfPanel.x - margins.x, margins.y)
		startPosition = Vector2(get_viewport_rect().size.x + margins.x, margins.y)
		rect_global_position = startPosition
		title.text = titleString
		label.text = labelString
		running = type
		show()
		tween.interpolate_property(self, "rect_global_position", startPosition, targetPosition, 0.35, Tween.TRANS_CIRC, Tween.EASE_IN, delay)
		tween.start()
		initial = true
		yield(tween, "tween_completed")
		initial = false
		tween.interpolate_property(self, "rect_global_position", targetPosition, startPosition, 0.5, Tween.TRANS_LINEAR, Tween.EASE_OUT, time)
		tween.start()
		yield(tween, "tween_completed")
		hide()
		running = null

func _on_head_notification(title, text, time, delay, type):
	_show_notif(title, text, time, delay, type)
