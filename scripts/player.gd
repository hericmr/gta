# player.gd — Personagem a pé, top-down (Godot 3)
extends KinematicBody2D

const VELOCIDADE = 200.0
const FPS_ANIM   = 8.0
const N_FRAMES   = 8   # total de frames no sprite sheet (2 colunas × 4 linhas)

var _frame_timer = 0.0
var _frame_atual = 0

onready var _sprite : Sprite   = $Sprite
onready var _camera : Camera2D = $Camera2D

func _physics_process(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): dir.x += 1
	dir = dir.normalized()

	if dir != Vector2.ZERO:
		# Rotaciona para encarar a direção do movimento
		# (+PI/2 porque o sprite aponta para cima no repouso)
		rotation = dir.angle() + PI / 2.0

		_frame_timer += delta
		if _frame_timer >= 1.0 / FPS_ANIM:
			_frame_timer -= 1.0 / FPS_ANIM
			_frame_atual = (_frame_atual + 1) % N_FRAMES
			_sprite.frame = _frame_atual
	else:
		_frame_timer = 0.0
		_sprite.frame = 0

	move_and_slide(dir * VELOCIDADE)
