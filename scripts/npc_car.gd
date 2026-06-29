# npc_car.gd — Carro NPC (Godot 3)
# Lógica inspirada no GTA 1/2: velocidade alta, redução suave por proximidade,
# despawn automático quando travado.
extends KinematicBody2D

const DIST_WP   = 50.0

const MODELOS = [
	{
		"nome": "Sedan",
		"textura": preload("res://assets/carros/SP_021.png"),
		"max_speed": 774.0,
		"engine_power": 650.0,
		"braking": 550.0,
		"grip_normal": 4.8,
		"grip_drift": 0.5,
		"vel_mult": 1.0
	},
	{
		"nome": "Sports",
		"textura": preload("res://assets/carros/SP_029.png"),
		"max_speed": 980.0,
		"engine_power": 950.0,
		"braking": 700.0,
		"grip_normal": 3.8,
		"grip_drift": 0.4,
		"vel_mult": 1.25
	},
	{
		"nome": "Heavy",
		"textura": preload("res://assets/carros/SP_038.png"),
		"max_speed": 650.0,
		"engine_power": 480.0,
		"braking": 400.0,
		"grip_normal": 6.0,
		"grip_drift": 0.8,
		"vel_mult": 0.78
	},
	{
		"nome": "Compact",
		"textura": preload("res://assets/carros/SP_043.png"),
		"max_speed": 820.0,
		"engine_power": 750.0,
		"braking": 600.0,
		"grip_normal": 5.2,
		"grip_drift": 0.6,
		"vel_mult": 1.05
	}
]

# Detecção de veículo à frente
const CONE_FRENTE     = 0.92    # cos(~23°) — cone estreito: ignora cruzamentos

# Despawn por travamento: se mover < STUCK_DIST2 px em STUCK_TEMPO s → despawn
const STUCK_DIST2  = 150.0   # px mínimos em STUCK_TEMPO segundos
const STUCK_TEMPO  = 2.0     # intervalo de verificação (segundos)

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

var _wps:         PoolVector2Array = PoolVector2Array()
var _idx:         int   = 0
var _vel:         float = 350.0
var _terminado:   bool  = false
var _pos_check:   Vector2 = Vector2.ZERO
var _check_timer: float   = 0.0
var _stuck_t:     float   = 0.0
var _fator_cache: float = 1.0
var _fator_tick:  int     = 0
var modelo_idx:   int     = 0
var _sensor_peds: Area2D  = null

var _visual:      Polygon2D = null
var _sombra:      Polygon2D = null

signal chegou_ao_fim

var _congelado: bool = false


func congelar() -> void:
	if _congelado:
		return
	_congelado      = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask  = 0


func descongelar() -> void:
	if not _congelado:
		return
	_congelado      = false
	set_physics_process(true)
	collision_layer = 2
	collision_mask  = 3


func _ready() -> void:
	scale = Vector2(0.97, 0.97)
	add_to_group("npc_carros")

	modelo_idx = randi() % MODELOS.size()
	var modelo = MODELOS[modelo_idx]

	# ── Criar Sombra ──────────────────────────────────────────────────────────
	_sombra = Polygon2D.new()
	_sombra.name = "Sombra"
	_sombra.texture = modelo["textura"]
	_sombra.polygon = POLIGONO
	_sombra.position = Vector2(73.5, 150.0) + Vector2(5.0, 5.0)
	_sombra.rotation = PI
	_sombra.scale = Vector2(2.037, 1.944)
	_sombra.color = Color(0.0, 0.0, 0.0, 0.4)
	_sombra.z_index = -1
	add_child(_sombra)

	# ── Criar Visual ──────────────────────────────────────────────────────────
	_visual = Polygon2D.new()
	_visual.name = "Visual"
	_visual.texture  = modelo["textura"]
	_visual.polygon  = POLIGONO
	_visual.position = Vector2(73.5, 150.0)
	_visual.rotation = PI
	_visual.scale    = Vector2(2.037, 1.944)
	
	if modelo_idx == 3 and randf() < 0.5:
		_visual.color = Color(0.95, 0.82, 0.08) # Amarelo Táxi
	else:
		_visual.color = CORES[randi() % CORES.size()]
	add_child(_visual)

	var shape = RectangleShape2D.new()
	shape.extents = Vector2(30.0, 58.0)
	var col = CollisionShape2D.new()
	col.shape    = shape
	col.position = Vector2(37.5, 82.0)
	add_child(col)

	# Cria o sensor físico de pedestres (otimizado no C++ do motor)
	_sensor_peds = Area2D.new()
	_sensor_peds.collision_layer = 0
	_sensor_peds.collision_mask  = 8 # Camada 4: Pedestres e Player
	var s_shape = RectangleShape2D.new()
	s_shape.extents = Vector2(22.0, 80.0) # Largura 44px, comprimento 160px
	var s_col = CollisionShape2D.new()
	s_col.shape = s_shape
	s_col.position = Vector2(37.5, -56.0) # Centralizado em frente ao parachoque
	_sensor_peds.add_child(s_col)
	add_child(_sensor_peds)

	collision_layer = 2
	collision_mask  = 3
	z_index = 5


func inicializar(wps: PoolVector2Array, vel: float, start: int = 0) -> void:
	_wps       = wps
	_vel       = vel
	_fator_cache = 1.0
	_fator_tick  = 0
	
	var modelo = MODELOS[modelo_idx]
	_vel         = vel * modelo["vel_mult"]
	
	_terminado = false
	_stuck_t     = 0.0
	_check_timer = 0.0
	var n = wps.size()
	_idx = start if start < n else (n - 1 if n > 0 else 0)
	if _idx < _wps.size():
		position   = _wps[_idx]
		_pos_check = position
		if _idx + 1 < _wps.size():
			var dir = (_wps[_idx + 1] - _wps[_idx]).normalized()
			rotation = atan2(dir.y, dir.x) + PI * 0.5


# Troca de rota sem teletransportar — usado pelo grafo na continuação
func reinicializar(wps: PoolVector2Array, vel: float) -> void:
	_wps         = wps
	_vel         = vel
	_terminado   = false
	_stuck_t     = 0.0
	_check_timer = 0.0
	_pos_check   = position
	# Encontra o waypoint mais próximo na nova rua
	_idx = 0
	var melhor_d = INF
	for i in range(wps.size()):
		var d = position.distance_squared_to(wps[i])
		if d < melhor_d:
			melhor_d = d
			_idx = i
	# Avança além dos waypoints já ultrapassados
	while _idx < _wps.size() - 1 and position.distance_to(_wps[_idx]) < DIST_WP:
		_idx += 1


func receber_impacto(impulso: Vector2) -> void:
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

	if _sombra:
		_sombra.position = _visual.position + Vector2(5.0, 5.0).rotated(-rotation)

	# ── Detecção de travamento (amostra a cada STUCK_TEMPO segundos) ─────────
	_check_timer += delta
	if _check_timer >= STUCK_TEMPO:
		if position.distance_to(_pos_check) < STUCK_DIST2:
			# Pula 3 waypoints antes de desistir
			_idx = min(_idx + 3, _wps.size())
			if _idx >= _wps.size():
				_terminado = true
				emit_signal("chegou_ao_fim")
		_pos_check   = position
		_check_timer = 0.0


# Retorna fator 0..1 baseado na distância ao veículo mais próximo à frente.
# 1.0 = velocidade total; 0.0 = parado.
func _fator_proximidade() -> float:
	_fator_tick = (_fator_tick + 1) % 3
	if _fator_tick != 0:
		return _fator_cache

	var fwd = -transform.y
	var melhor: float = 1.0

	# Busca todos os tipos de veículos para evitar colisões
	var outros = get_tree().get_nodes_in_group("npc_carros") + \
	             get_tree().get_nodes_in_group("npc_onibus") + \
	             get_tree().get_nodes_in_group("player_car")

	for outro in outros:
		if outro == self or not is_instance_valid(outro):
			continue

		var delta_pos = outro.position - position
		var dist = delta_pos.length()

		# Comprimento dinâmico baseado no tipo de veículo (para distância de colisão origin-to-origin)
		var half_len_outro = 58.0
		if outro.is_in_group("npc_onibus"):
			half_len_outro = 83.0
		elif outro.is_in_group("player_car"):
			half_len_outro = 61.0

		var dist_min = 58.0 + half_len_outro + 35.0  # 35px de margem de segurança bumper-to-bumper
		var dist_max = dist_min + 200.0              # zona de desaceleração suave de 200px

		if dist > dist_max:
			continue
		if fwd.dot(delta_pos / dist) < CONE_FRENTE:
			continue

		var f = (dist - dist_min) / (dist_max - dist_min)
		if f < melhor:
			melhor = f

	# Evita atropelamento de pedestres e do Player a pé usando o Area2D (O(1) no script)
	if is_instance_valid(_sensor_peds):
		for ped in _sensor_peds.get_overlapping_bodies():
			if not is_instance_valid(ped) or ped.get("no_onibus") or ped.get("_morto"):
				continue

			var delta_pos = ped.position - position
			var dist = delta_pos.length()

			var dist_min = 58.0 + 10.0 + 35.0  # 58px (carro) + 10px (pedestre) + 35px margem
			var dist_max = dist_min + 140.0

			var f = (dist - dist_min) / (dist_max - dist_min)
			if f < melhor:
				melhor = f

	_fator_cache = clamp(melhor, 0.0, 1.0)
	return _fator_cache
