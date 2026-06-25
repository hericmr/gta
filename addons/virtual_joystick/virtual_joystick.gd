# virtual_joystick.gd — Virtual Joystick para Godot 3.x
# API compatível com MarcoFazioRandom/Virtual-Joystick-Godot (branch Godot3)
tool
extends Control

enum VisibilityMode { ALWAYS, TOUCHSCREEN_ONLY }
enum JoystickMode   { FIXED, DYNAMIC }

export(float)  var joystick_radius:   float  = 100.0
export(float)  var dead_zone:         float  = 0.2
export(bool)   var use_input_actions: bool   = true
export(String) var action_left:       String = "ui_left"
export(String) var action_right:      String = "ui_right"
export(String) var action_up:         String = "ui_up"
export(String) var action_down:       String = "ui_down"
export(int, "Always", "Touchscreen Only") var visibility_mode: int = VisibilityMode.TOUCHSCREEN_ONLY
export(int, "Fixed", "Dynamic")           var joystick_mode:   int = JoystickMode.DYNAMIC
export(Color) var color_base: Color = Color(1.0, 1.0, 1.0, 0.22)
export(Color) var color_knob: Color = Color(1.0, 1.0, 1.0, 0.42)

# Leitura pública: vetor normalizado [-1,1] em cada eixo
var output: Vector2 = Vector2.ZERO

var _touch_index: int      = -1
var _base_center: Vector2  = Vector2.ZERO
var _knob_pos:    Vector2  = Vector2.ZERO
var _active:      bool     = false
var _prev:        Dictionary = {}


func _ready() -> void:
	if visibility_mode == VisibilityMode.TOUCHSCREEN_ONLY and not OS.has_touchscreen_ui_hint():
		visible = false
		return
	# rect_size pode ser zero em _ready; usa notificação de resize para garantir valor correto
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
				_knob_pos = _base_center
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
		offset    = offset.normalized() * joystick_radius
		_knob_pos = _base_center + offset
	output = offset / joystick_radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	if use_input_actions:
		_fire_actions()
	update()


func _fire_actions() -> void:
	_set_action(action_left,  output.x < -dead_zone)
	_set_action(action_right, output.x >  dead_zone)
	_set_action(action_up,    output.y < -dead_zone)
	_set_action(action_down,  output.y >  dead_zone)


func _set_action(action: String, pressed: bool) -> void:
	if action.empty() or not InputMap.has_action(action):
		return
	if _prev.get(action, false) == pressed:
		return
	_prev[action] = pressed
	var ev        = InputEventAction.new()
	ev.action     = action
	ev.pressed    = pressed
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
		_set_action(action_left,  false)
		_set_action(action_right, false)
		_set_action(action_up,    false)
		_set_action(action_down,  false)
	_prev.clear()
	update()


func _draw() -> void:
	if Engine.editor_hint:
		return
	var center: Vector2 = rect_size / 2.0
	if not _active:
		draw_arc(center, joystick_radius,        0.0, TAU, 64, Color(1, 1, 1, 0.45), 4.0)
		draw_arc(center, joystick_radius * 0.35, 0.0, TAU, 32, Color(1, 1, 1, 0.30), 3.0)
		return
	# Base ativa
	draw_circle(_base_center, joystick_radius, color_base)
	draw_arc(_base_center, joystick_radius, 0.0, TAU, 64, Color(1, 1, 1, 0.32), 2.5)
	# Knob
	var kr: float = joystick_radius * 0.38
	draw_circle(_knob_pos, kr, color_knob)
	draw_arc(_knob_pos, kr, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.0)
