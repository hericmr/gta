# virtual_joystick.gd — Joystick virtual 2D para movimento do player (Godot 3.x)
tool
extends Control

enum VisibilityMode { ALWAYS, TOUCHSCREEN_ONLY }
enum JoystickMode   { FIXED, DYNAMIC }

export(float) var joystick_radius:   float = 105.0
export(float) var dead_zone:         float = 0.18
export(bool)  var use_input_actions: bool  = true
export(int, "Always", "Touchscreen Only") var visibility_mode: int = VisibilityMode.TOUCHSCREEN_ONLY
export(int, "Fixed", "Dynamic")           var joystick_mode:   int = JoystickMode.DYNAMIC
export(Color) var color_base: Color = Color(1.0, 1.0, 1.0, 0.22)
export(Color) var color_knob: Color = Color(1.0, 1.0, 1.0, 0.42)

# Saída pública: vetor 2D normalizado [-1,1] em cada eixo
var output: Vector2 = Vector2.ZERO

var _touch_index: int      = -1
var _base_center: Vector2  = Vector2.ZERO
var _knob_pos:    Vector2  = Vector2.ZERO
var _active:      bool     = false
var _prev:        Dictionary = {}


func _ready() -> void:
	add_to_group("virtual_joystick")
	if visibility_mode == VisibilityMode.TOUCHSCREEN_ONLY and not OS.has_touchscreen_ui_hint():
		visible = false
		return
	_reset_center()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reset_center()
		update()
	elif what == NOTIFICATION_WM_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release_all()


func _input(event: InputEvent) -> void:
	if not visible or Engine.editor_hint:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and get_global_rect().has_point(event.position):
				_touch_index = event.index
				_active      = true
				if joystick_mode == JoystickMode.DYNAMIC:
					_base_center = event.position - rect_global_position
				_knob_pos = event.position - rect_global_position
				_update()
				get_tree().set_input_as_handled()
		else:
			if event.index == _touch_index:
				_release_all()
				get_tree().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_knob_pos = event.position - rect_global_position
			_update()
			get_tree().set_input_as_handled()


func _update() -> void:
	var offset: Vector2 = _knob_pos - _base_center
	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius
	_knob_pos = _base_center + offset

	var raw = offset / joystick_radius
	output   = raw if raw.length() >= dead_zone else Vector2.ZERO

	if use_input_actions:
		_fire_actions()
	update()


func _fire_actions() -> void:
	_set_action("ui_up",    output.y < -dead_zone)
	_set_action("ui_down",  output.y >  dead_zone)
	_set_action("ui_left",  output.x < -dead_zone)
	_set_action("ui_right", output.x >  dead_zone)


func _set_action(action: String, pressed: bool) -> void:
	if action.empty() or not InputMap.has_action(action):
		return
	if _prev.get(action, false) == pressed:
		return
	_prev[action] = pressed
	var ev     = InputEventAction.new()
	ev.action  = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _reset_center() -> void:
	if not _active:
		_base_center = rect_size / 2.0
		_knob_pos    = _base_center


func _release_all() -> void:
	if not _active:
		return
	_touch_index = -1
	_active      = false
	output       = Vector2.ZERO
	_reset_center()
	if use_input_actions:
		_set_action("ui_up",    false)
		_set_action("ui_down",  false)
		_set_action("ui_left",  false)
		_set_action("ui_right", false)
	_prev.clear()
	update()


func _draw() -> void:
	if Engine.editor_hint:
		return

	var center: Vector2 = _base_center if _active else rect_size / 2.0
	var kr: float       = joystick_radius * 0.40

	# Anel externo (base)
	draw_arc(center, joystick_radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.30), 3.0)
	draw_circle(center, joystick_radius, Color(color_base.r, color_base.g, color_base.b, color_base.a * (0.6 if _active else 1.0)))

	# Knob central
	draw_circle(_knob_pos, kr, color_knob)
	draw_arc(_knob_pos, kr, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.55), 2.0)
