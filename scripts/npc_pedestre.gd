# npc_pedestre.gd — Pedestre NPC com mesmo asset e tamanho do player (Godot 3)
extends KinematicBody2D

const DIST_WP   = 12.0
const FPS_ANIM  = 8.0
const N_FRAMES  = 5

# Modulações de cor para variar a aparência (tinta sobre o sprite original)
const CORES = [
	Color(1.00, 1.00, 1.00),  # original
	Color(0.70, 0.85, 1.00),  # azulado
	Color(1.00, 0.75, 0.75),  # avermelhado
	Color(0.75, 1.00, 0.75),  # esverdeado
	Color(1.00, 0.92, 0.65),  # amarelado
	Color(0.85, 0.75, 1.00),  # arroxeado
	Color(0.65, 0.65, 0.65),  # cinza
	Color(0.60, 0.40, 0.25),  # marrom
]

var _wps:         PoolVector2Array = PoolVector2Array()
var _idx:         int   = 0
var _vel:         float = 10.0
var _terminado:   bool  = false
var _frame_timer: float = 0.0
var _frame_atual: int   = 0
var _sprite:      Sprite = null

signal chegou_ao_fim


func _ready() -> void:
	# Sprite idêntico ao Player.tscn
	_sprite          = Sprite.new()
	_sprite.texture  = load("res://assets/human/player_walk.png")
	_sprite.hframes  = N_FRAMES
	_sprite.position = Vector2(0.0, -2.0)
	_sprite.scale    = Vector2(2.08, 1.85)
	_sprite.modulate = CORES[randi() % CORES.size()]
	add_child(_sprite)

	# Colisão idêntica ao Player.tscn
	var shape = CircleShape2D.new()
	shape.radius = 7.9
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	collision_layer = 8
	collision_mask  = 1


func inicializar(wps: PoolVector2Array, vel: float, start: int = 0) -> void:
	_wps       = wps
	_vel       = vel
	_terminado = false
	_frame_atual  = randi() % N_FRAMES   # começa em frame aleatório
	_frame_timer  = 0.0
	_idx = clamp(start, 0, max(0, wps.size() - 1))
	if _idx < _wps.size():
		position = _wps[_idx]


func _physics_process(delta: float) -> void:
	if _idx >= _wps.size():
		if not _terminado:
			_terminado = true
			emit_signal("chegou_ao_fim")
		if _sprite:
			_sprite.frame = 0
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	if dist < DIST_WP:
		_idx += 1
		return

	rotation = atan2(diff.y, diff.x) - PI * 0.5
	move_and_slide((diff / dist) * _vel)

	# Animação de caminhada
	_frame_timer += delta
	if _frame_timer >= 1.0 / FPS_ANIM:
		_frame_timer -= 1.0 / FPS_ANIM
		_frame_atual  = (_frame_atual + 1) % N_FRAMES
		if _sprite:
			_sprite.frame = _frame_atual
