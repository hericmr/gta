# player.gd — Personagem a pé, controle estilo GTA 2 (Godot 3)
# A/D ou setas laterais: giram no próprio eixo
# W/S ou setas cima/baixo: avançam/recuam na direção que o player enfrenta
extends KinematicBody2D

const VELOCIDADE     = 200.0
const VELOCIDADE_RE  = 100.0
const VEL_ROTACAO    = 180.0  # graus por segundo
const FPS_ANIM       = 8.0
const N_FRAMES       = 8

var ativo        = true
var _frame_timer = 0.0
var _frame_atual = 0

onready var _sprite : Sprite   = $Sprite
onready var _camera : Camera2D = $Camera2D

func _ready() -> void:
	_criar_sombra(Vector2(1, 5), Vector2(9, 4))

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

	# ── Avanço / recuo na direção que o sprite enfrenta ─────────────────────
	var av = 0.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		av =  1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		av = -1.0

	var vel_final = -transform.y * av * (VELOCIDADE if av > 0 else VELOCIDADE_RE)
	move_and_slide(vel_final)

	# ── Animação de frames ───────────────────────────────────────────────────
	if av != 0.0:
		_frame_timer += delta
		if _frame_timer >= 1.0 / FPS_ANIM:
			_frame_timer -= 1.0 / FPS_ANIM
			_frame_atual = (_frame_atual + 1) % N_FRAMES
			_sprite.frame = _frame_atual
	else:
		_frame_timer = 0.0
		_sprite.frame = 0

func _criar_sombra(centro: Vector2, semi_eixos: Vector2) -> void:
	var s = Polygon2D.new()
	var pts = PoolVector2Array()
	for i in range(16):
		var a = 2.0 * PI * i / 16.0
		pts.append(centro + Vector2(cos(a) * semi_eixos.x, sin(a) * semi_eixos.y))
	s.polygon = pts
	s.color   = Color(0, 0, 0, 0.38)
	s.z_index = -1
	add_child(s)
	move_child(s, 0)
