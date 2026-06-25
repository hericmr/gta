# player.gd — Personagem a pé, top-down (Godot 3)
extends KinematicBody2D

const VELOCIDADE    = 200.0
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

onready var _sprite : Sprite   = $Sprite
onready var _camera : Camera2D = $Camera2D

func _physics_process(delta: float) -> void:
	if not ativo:
		return

	_tiro_cd = max(0.0, _tiro_cd - delta)
	if Input.is_key_pressed(KEY_CONTROL) and _tiro_cd <= 0.0:
		_disparar()
		_tiro_cd = TIRO_COOLDOWN

	# A/D giram no próprio eixo
	var giro = 0.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): giro =  1.0
	elif Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): giro = -1.0
	rotation_degrees += giro * VEL_ROTACAO * delta

	# W/S avançam/recuam na direção que o sprite está olhando
	var av = 0.0
	if Input.is_action_pressed("ui_up")   or Input.is_key_pressed(KEY_W): av =  1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S): av = -1.0

	var vel = transform.y * av * (VELOCIDADE if av > 0 else VELOCIDADE_RE)
	move_and_slide(vel)

	# Animação
	if av != 0.0:
		_frame_timer += delta
		if _frame_timer >= 1.0 / FPS_ANIM:
			_frame_timer -= 1.0 / FPS_ANIM
			_frame_atual = (_frame_atual + 1) % N_FRAMES
			_sprite.frame = _frame_atual
	else:
		_frame_timer = 0.0
		_sprite.frame = 0


func _disparar() -> void:
	var b = BulletScript.new()
	get_parent().add_child(b)
	b.position = position
	b.iniciar(transform.y)
