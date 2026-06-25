# touch_button.gd — Botão de toque circular para mobile (Godot 3.x)
# Dispara a action configurada via Input.parse_input_event.
# Funciona com "Emulate Mouse from Touch" = OFF.
extends Control

export(String) var action_name:     String = ""
export(String) var label_text:      String = "BTN"
export(float)  var radius:          float  = 52.0
export(Color)  var color_normal:    Color  = Color(0.10, 0.10, 0.40, 0.60)
export(Color)  var color_pressed:   Color  = Color(0.30, 0.30, 0.90, 0.85)
export(Color)  var color_border:    Color  = Color(1.00, 1.00, 1.00, 0.50)
export(bool)   var touchscreen_only: bool  = true

var _pressed:     bool = false
var _touch_index: int  = -1


func _ready() -> void:
	if touchscreen_only and not OS.has_touchscreen_ui_hint():
		visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if get_global_rect().has_point(event.position):
				_touch_index = event.index
				_pressed     = true
				_fire(true)
				update()
				get_tree().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_release()
			get_tree().set_input_as_handled()


func _release() -> void:
	if not _pressed:
		return
	_touch_index = -1
	_pressed     = false
	_fire(false)
	update()


func _fire(is_pressed: bool) -> void:
	if action_name.empty() or not InputMap.has_action(action_name):
		return
	var ev     = InputEventAction.new()
	ev.action  = action_name
	ev.pressed = is_pressed
	Input.parse_input_event(ev)


func _draw() -> void:
	var center: Vector2 = rect_size / 2.0
	var col: Color = color_pressed if _pressed else color_normal
	draw_circle(center, radius, col)
	draw_arc(center, radius, 0.0, TAU, 48, color_border, 2.5)
	if not label_text.empty():
		var font: Font = get_font("font", "Label")
		if font:
			var sz: Vector2 = font.get_string_size(label_text)
			var tp: Vector2 = center + Vector2(-sz.x * 0.5, sz.y * 0.3)
			draw_string(font, tp, label_text, Color(1, 1, 1, 0.95))
