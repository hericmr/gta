# player.gd — Personagem a pé, top-down (Godot 3)
extends KinematicBody2D

const VELOCIDADE    = 240.0
const VELOCIDADE_RE = 100.0
const VEL_ROTACAO   = 230.0
const FPS_ANIM      = 8.0
const N_FRAMES      = 5
const TIRO_COOLDOWN = 0.12

const BulletScript = preload("res://scripts/bullet.gd")

var ativo        = true
var _frame_timer = 0.0
var _frame_atual = 0
var _tiro_cd     = 0.0
var _joy         = null

onready var _sprite : Sprite   = $Sprite
onready var _sombra : Sprite   = $Sombra
onready var _camera : Camera2D = $Camera2D

func _physics_process(delta: float) -> void:
	if not ativo:
		return

	_tiro_cd = max(0.0, _tiro_cd - delta)
	if (Input.is_action_pressed("atirar") or Input.is_key_pressed(KEY_CONTROL)) and _tiro_cd <= 0.0:
		_disparar()
		_tiro_cd = TIRO_COOLDOWN

	# ── Mobile: joystick analógico ────────────────────────────────────────────
	var joy = _joystick()
	if joy != null and joy.output.length() > joy.dead_zone:
		var dir = joy.output
		# ângulo no padrão do Godot: atan2(y,x) - 90° para que "cima" = rotation 0
		rotation = atan2(dir.y, dir.x) - PI * 0.5
		move_and_slide(dir.normalized() * VELOCIDADE)
		_animar(delta)
		return

	# ── Teclado: controles de tanque ─────────────────────────────────────────
	var giro = 0.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): giro =  1.0
	elif Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): giro = -1.0
	rotation_degrees += giro * VEL_ROTACAO * delta

	var av = 0.0
	if Input.is_action_pressed("ui_up")   or Input.is_key_pressed(KEY_W): av =  1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S): av = -1.0

	move_and_slide(transform.y * av * (VELOCIDADE if av > 0 else VELOCIDADE_RE))

	if av != 0.0:
		_animar(delta)
	else:
		_frame_timer  = 0.0
		_sprite.frame = 0
		_sombra.frame = 0


func _animar(delta: float) -> void:
	_frame_timer += delta
	if _frame_timer >= 1.0 / FPS_ANIM:
		_frame_timer -= 1.0 / FPS_ANIM
		_frame_atual  = (_frame_atual + 1) % N_FRAMES
		_sprite.frame = _frame_atual
		_sombra.frame = _frame_atual


func _joystick():
	if _joy == null or not is_instance_valid(_joy):
		var nos = get_tree().get_nodes_in_group("virtual_joystick")
		_joy = nos[0] if not nos.empty() else null
	return _joy


func _disparar() -> void:
	var b = BulletScript.new()
	get_parent().add_child(b)
	b.position = position
	b.iniciar(transform.y)
