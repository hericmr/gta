# player.gd — Personagem a pé, controle estilo GTA 2 (Godot 3)
extends KinematicBody2D

const VELOCIDADE     = 200.0
const VELOCIDADE_RE  = 100.0
const VEL_ROTACAO    = 180.0
const FPS_ANIM       = 8.0
const N_FRAMES       = 8

var ativo        = true
var _frame_timer = 0.0
var _frame_atual = 0
var _sombras     : Array = []

onready var _sprite : Sprite   = $Sprite
onready var _camera : Camera2D = $Camera2D

func _ready() -> void:
	# 3 camadas: escala [1.05→1.25], opacidade decrescente → sombra escura com borda difusa
	var escalas    = [1.05, 1.15, 1.25]
	var opacidades = [0.42, 0.26, 0.10]
	for i in range(3):
		var s      = Sprite.new()
		s.texture  = _sprite.texture
		s.hframes  = _sprite.hframes
		s.vframes  = _sprite.vframes
		s.frame    = 0
		s.position = _sprite.position
		s.scale    = _sprite.scale * escalas[i]
		s.modulate = Color(0, 0, 0, opacidades[i])
		s.z_index  = -1
		add_child(s)
		move_child(s, 0)
		_sombras.append(s)

func _physics_process(delta: float) -> void:
	if not ativo:
		return

	# ── Rotação no próprio eixo ──────────────────────────────────────────────
	var giro = 0.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		giro =  1.0
	elif Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		giro = -1.0
	rotation_degrees += giro * VEL_ROTACAO * delta

	# ── Avanço / recuo ───────────────────────────────────────────────────────
	var av = 0.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		av =  1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		av = -1.0

	var vel_final = -transform.y * av * (VELOCIDADE if av > 0 else VELOCIDADE_RE)
	move_and_slide(vel_final)

	# ── Animação ─────────────────────────────────────────────────────────────
	if av != 0.0:
		_frame_timer += delta
		if _frame_timer >= 1.0 / FPS_ANIM:
			_frame_timer -= 1.0 / FPS_ANIM
			_frame_atual = (_frame_atual + 1) % N_FRAMES
			_sprite.frame = _frame_atual
	else:
		_frame_timer  = 0.0
		_sprite.frame = 0

	for s in _sombras:
		s.frame = _sprite.frame
