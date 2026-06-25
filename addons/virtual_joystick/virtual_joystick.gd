# virtual_steering.gd — Controle de Direção Horizontal para Godot 3.x
tool
extends Control

enum VisibilityMode { ALWAYS, TOUCHSCREEN_ONLY }
enum JoystickMode   { FIXED, DYNAMIC }

# Substituímos o raio por uma "largura do slider"
export(float)  var slider_width:  float  = 100.0 
export(float)  var dead_zone:     float  = 0.1
export(bool)   var use_input_actions: bool   = true
export(String) var action_left:       String = "ui_left"
export(String) var action_right:      String = "ui_right"
export(int, "Always", "Touchscreen Only") var visibility_mode: int = VisibilityMode.TOUCHSCREEN_ONLY
export(int, "Fixed", "Dynamic")           var joystick_mode:   int = JoystickMode.DYNAMIC
export(Color) var color_base: Color = Color(1.0, 1.0, 1.0, 0.22)
export(Color) var color_knob: Color = Color(1.0, 1.0, 1.0, 0.42)

# Leitura pública: valor float [-1, 1] no eixo X
var output: float = 0.0 

var _touch_index: int      = -1
var _base_center: Vector2  = Vector2.ZERO
var _knob_pos:    Vector2  = Vector2.ZERO
var _active:      bool     = false
var _prev:        Dictionary = {}


func _ready() -> void:
	add_to_group("virtual_steering")
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
	# Calculamos apenas o deslocamento no eixo X
	var offset_x: float = _knob_pos.x - _base_center.x
	
	# Limitamos o deslocamento máximo à largura do slider
	if abs(offset_x) > slider_width:
		offset_x = sign(offset_x) * slider_width
		
	# TRAVA O EIXO Y: O knob mantém a mesma altura (Y) do centro base
	_knob_pos = Vector2(_base_center.x + offset_x, _base_center.y)
	
	# Calcula a saída normalizada (-1.0 a 1.0)
	output = offset_x / slider_width
	
	if abs(output) < dead_zone:
		output = 0.0
		
	if use_input_actions:
		_fire_actions()
	update()


func _fire_actions() -> void:
	_set_action(action_left,  output < -dead_zone)
	_set_action(action_right, output >  dead_zone)


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
	output       = 0.0
	_reset_center()
	if use_input_actions:
		_set_action(action_left,  false)
		_set_action(action_right, false)
	_prev.clear()
	update()


func _draw() -> void:
	if Engine.editor_hint:
		return
		
	var center: Vector2 = rect_size / 2.0
	# Definimos os limites da trilha visual desenhada
	var track_start: Vector2 = Vector2(-slider_width, 0)
	var track_end: Vector2 = Vector2(slider_width, 0)
	var kr: float = slider_width * 0.38
	
	if not _active:
		# Base inativa - desenha a linha da "trilha" e o botão central
		draw_line(center + track_start, center + track_end, Color(1, 1, 1, 0.30), 8.0)
		draw_circle(center, kr, Color(1, 1, 1, 0.45))
		return
		
	# Base ativa
	draw_line(_base_center + track_start, _base_center + track_end, color_base, 10.0)
	
	# Knob ativo (sempre sobre o eixo X)
	draw_circle(_knob_pos, kr, color_knob)
	draw_arc(_knob_pos, kr, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.0)
