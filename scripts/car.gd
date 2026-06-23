# car.gd — Física arcade do carro top-down (KinematicBody2D — Godot 3)
extends KinematicBody2D

export var velocidade_maxima: float  = 500.0
export var aceleracao: float         = 400.0
export var atrito: float             = 300.0
export var frenagem: float           = 900.0   # desaceleração ao frear
export var velocidade_re: float      = 0.4     # fração da vel. máxima em ré

var em_uso: bool = false
var _vel: float  = 0.0
var _loader      = null

onready var _camera: Camera2D          = $Camera2D
onready var _radio:  AudioStreamPlayer = $Radio

signal velocidade_mudou(kmh)

func _ready() -> void:
	_radio.connect("finished", self, "_on_radio_finished")
	_loader = ResourceLoader.load_interactive("res://assets/radio/SLUS-00789_BIL001.mp3")

func _on_radio_finished() -> void:
	_radio.play()

func _process(_delta: float) -> void:
	if _loader == null:
		return
	var err = _loader.poll()
	if err == ERR_FILE_EOF:
		_radio.stream = _loader.get_resource()
		_radio.play()
		_loader = null
	elif err != OK:
		_loader = null  # arquivo não encontrado, ignora sem travar

func _physics_process(delta: float) -> void:
	if not em_uso:
		return

	# ── Entrada ──────────────────────────────────────────────────────────────
	var av: float = 0.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		av = 1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		av = -1.0

	var dir: float = 0.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir = 1.0
	elif Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir = -1.0

	# ── Velocidade (estilo GTA) ───────────────────────────────────────────────
	if av > 0.0:
		# Acelera para frente
		_vel = move_toward(_vel, velocidade_maxima, aceleracao * delta)
	elif av < 0.0:
		if _vel > 30.0:
			# Frear: estava indo para frente → desacelera forte
			_vel = move_toward(_vel, 0.0, frenagem * delta)
		else:
			# Ré: carro parado ou quase parado
			_vel = move_toward(_vel, -velocidade_maxima * velocidade_re, aceleracao * delta)
	else:
		# Sem input: atrito passivo
		_vel = move_toward(_vel, 0.0, atrito * delta)

	# ── Rotação ──────────────────────────────────────────────────────────────
	var fator: float = clamp(abs(_vel) / velocidade_maxima, 0.0, 1.0)
	rotation_degrees += dir * 140.0 * fator * sign(_vel) * delta

	# ── Movimento ────────────────────────────────────────────────────────────
	move_and_slide(-transform.y * _vel, Vector2.ZERO)

	# ── Zoom dinâmico ────────────────────────────────────────────────────────
	var zoom_alvo: float = lerp(1.3, 0.80, fator)
	_camera.zoom = lerp(_camera.zoom, Vector2(zoom_alvo, zoom_alvo), 4.0 * delta)

	emit_signal("velocidade_mudou", abs(_vel) * 0.18)
