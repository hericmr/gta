# npc_car.gd — Carro NPC com mesmo asset e tamanho do carro do jogador (Godot 3)
extends KinematicBody2D

const DIST_WP = 50.0

const CORES = [
	Color(0.80, 0.20, 0.20),  # vermelho
	Color(0.20, 0.42, 0.85),  # azul
	Color(0.18, 0.62, 0.24),  # verde
	Color(0.85, 0.78, 0.10),  # amarelo
	Color(0.50, 0.20, 0.68),  # roxo
	Color(0.88, 0.44, 0.08),  # laranja
	Color(0.28, 0.28, 0.28),  # cinza escuro
	Color(0.92, 0.92, 0.92),  # prata
	Color(0.55, 0.35, 0.15),  # marrom
]

# Polígono idêntico ao Car.tscn
const POLIGONO = PoolVector2Array([
	Vector2(1.756, 60.375),   Vector2(1.756, 45.281),
	Vector2(1.756, 38.813),   Vector2(1.756, 30.188),
	Vector2(0.878, 20.484),   Vector2(2.634, 9.703),
	Vector2(4.390, 4.313),    Vector2(7.024, 2.156),
	Vector2(9.659, 0.0),      Vector2(17.561, 1.078),
	Vector2(24.585, 1.078),   Vector2(31.610, 3.234),
	Vector2(35.122, 15.094),  Vector2(34.244, 23.719),
	Vector2(33.366, 38.813),  Vector2(33.366, 42.047),
	Vector2(33.366, 47.438),  Vector2(34.244, 57.141),
	Vector2(29.854, 65.766),  Vector2(9.658, 65.766),
])

var _wps:       PoolVector2Array = PoolVector2Array()
var _idx:       int   = 0
var _vel:       float = 350.0
var _terminado: bool  = false

signal chegou_ao_fim


func _ready() -> void:
	# Visual idêntico ao Car.tscn: mesma posição, rotação, escala e textura
	var v = Polygon2D.new()
	v.texture  = load("res://assets/carros/SP_021.png")
	v.polygon  = POLIGONO
	v.position = Vector2(87.715, 167.5)
	v.rotation = PI
	v.scale    = Vector2(2.86, 2.36)
	v.color    = CORES[randi() % CORES.size()]
	add_child(v)

	# Colisão idêntica ao Car.tscn
	var shape = RectangleShape2D.new()
	shape.extents = Vector2(41.25, 70.0)
	var col = CollisionShape2D.new()
	col.shape    = shape
	col.position = Vector2(36.25, 87.5)
	add_child(col)

	# Colide com prédios (layer 1) e com outros NPCs (layer 2); player passa por cima
	collision_layer = 2
	collision_mask  = 3


func inicializar(wps: PoolVector2Array, vel: float, start: int = 0) -> void:
	_wps       = wps
	_vel       = vel
	_terminado = false
	_idx       = clamp(start, 0, max(0, wps.size() - 1))
	if _idx < _wps.size():
		position = _wps[_idx]
		if _idx + 1 < _wps.size():
			var dir = (_wps[_idx + 1] - _wps[_idx]).normalized()
			rotation = atan2(dir.y, dir.x) + PI * 0.5


func _physics_process(_delta: float) -> void:
	if _idx >= _wps.size():
		if not _terminado:
			_terminado = true
			emit_signal("chegou_ao_fim")
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	if dist < DIST_WP:
		_idx += 1
		return

	rotation = atan2(diff.y, diff.x) + PI * 0.5
	move_and_slide(-transform.y * _vel)
