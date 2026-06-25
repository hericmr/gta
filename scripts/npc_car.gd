# npc_car.gd — Carro NPC (Godot 3)
# Lógica inspirada no GTA 1/2: velocidade alta, redução suave por proximidade,
# despawn automático quando travado.
extends KinematicBody2D

const DIST_WP   = 50.0
const TEX_CARRO = preload("res://assets/carros/SP_021.png")

# Detecção de veículo à frente
const DIST_FRENTE_MAX = 220.0   # começa a desacelerar a esta distância
const DIST_FRENTE_MIN = 70.0    # distância mínima (abaixo = para)
const CONE_FRENTE     = 0.65    # cos(~49°) — ângulo do cone de detecção

# Despawn por travamento (GTA 1/2: veículo preso some e reaparece)
const STUCK_DIST2  = 100.0   # deslocamento² mínimo por intervalo
const STUCK_TEMPO  = 3.5     # segundos parado antes de despawnar

const CORES = [
	Color(0.80, 0.20, 0.20), Color(0.20, 0.42, 0.85),
	Color(0.18, 0.62, 0.24), Color(0.85, 0.78, 0.10),
	Color(0.50, 0.20, 0.68), Color(0.88, 0.44, 0.08),
	Color(0.28, 0.28, 0.28), Color(0.92, 0.92, 0.92),
	Color(0.55, 0.35, 0.15),
]

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
var _pos_ant:   Vector2 = Vector2.ZERO
var _stuck_t:   float   = 0.0

signal chegou_ao_fim


func _ready() -> void:
	add_to_group("npc_carros")

	var v = Polygon2D.new()
	v.texture  = TEX_CARRO
	v.polygon  = POLIGONO
	v.position = Vector2(87.715, 167.5)
	v.rotation = PI
	v.scale    = Vector2(2.86, 2.36)
	v.color    = CORES[randi() % CORES.size()]
	add_child(v)

	var shape = RectangleShape2D.new()
	shape.extents = Vector2(41.25, 70.0)
	var col = CollisionShape2D.new()
	col.shape    = shape
	col.position = Vector2(36.25, 87.5)
	add_child(col)

	collision_layer = 2
	collision_mask  = 3
	z_index = 5


func inicializar(wps: PoolVector2Array, vel: float, start: int = 0) -> void:
	_wps       = wps
	_vel       = vel
	_terminado = false
	_stuck_t   = 0.0
	var n = wps.size()
	_idx = start if start < n else (n - 1 if n > 0 else 0)
	if _idx < _wps.size():
		position  = _wps[_idx]
		_pos_ant  = position
		if _idx + 1 < _wps.size():
			var dir = (_wps[_idx + 1] - _wps[_idx]).normalized()
			rotation = atan2(dir.y, dir.x) + PI * 0.5


func receber_impacto(impulso: Vector2) -> void:
	# Chamado pelo carro do player ao colidir
	pass


func _physics_process(delta: float) -> void:
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

	var fator = _fator_proximidade()
	move_and_slide(-transform.y * _vel * fator)

	# ── Despawn por travamento ────────────────────────────────────────────────
	if position.distance_squared_to(_pos_ant) < STUCK_DIST2:
		_stuck_t += delta
		if _stuck_t >= STUCK_TEMPO:
			_stuck_t   = 0.0
			_terminado = true
			emit_signal("chegou_ao_fim")
	else:
		_stuck_t = 0.0
	_pos_ant = position


# Retorna fator 0..1 baseado na distância ao veículo mais próximo à frente.
# 1.0 = velocidade total; 0.0 = parado.
func _fator_proximidade() -> float:
	var fwd = -transform.y
	var melhor: float = 1.0
	for outro in get_tree().get_nodes_in_group("npc_carros"):
		if outro == self or not is_instance_valid(outro):
			continue
		var delta_pos = outro.position - position
		var dist = delta_pos.length()
		if dist > DIST_FRENTE_MAX:
			continue
		if fwd.dot(delta_pos / dist) < CONE_FRENTE:
			continue
		var f = (dist - DIST_FRENTE_MIN) / (DIST_FRENTE_MAX - DIST_FRENTE_MIN)
		if f < melhor:
			melhor = f
	return clamp(melhor, 0.0, 1.0)
