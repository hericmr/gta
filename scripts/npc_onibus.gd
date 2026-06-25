# npc_onibus.gd — Ônibus NPC que segue rotas reais de Santos (Godot 3)
extends KinematicBody2D

# Física do ônibus: mais lento, aceleração/frenagem suaves, maior inércia
const MAX_SPEED       = 420.0
const ENGINE_POWER    = 120.0
const BRAKING_POWER   = 85.0

# Thresholds de waypoint / parada
const DIST_WP           = 80.0
const DIST_INICIO_FREAR = 350.0
const DIST_PARADO       = 40.0
const ESPERA_PARADA_MIN = 3.0
const ESPERA_PARADA_MAX = 6.0

# Embarque / desembarque
const RAIO_EMBARQUE    = 180.0   # raio para capturar pedestres na parada (px)
const MAX_PASSAGEIROS  = 30      # lotação máxima
const PROB_EMBARQUE    = 0.65    # chance de um pedestre próximo embarcar
const PROB_DESEMBARQUE = 0.45    # chance de desembarcar em cada parada
const OFFSET_SAIDA     = 70.0    # distância lateral ao sair do ônibus

const _TEX_PATH = "res://assets/carros/SP_013.png"

enum Estado { DIRIGINDO, FREANDO_PARADA, PARADO_PONTO }

var _wps:         PoolVector2Array = PoolVector2Array()
var _paradas_idx: Array  = []
var _idx:         int    = 0
var _speed:       float  = 0.0
var _estado:      int    = Estado.DIRIGINDO
var _wait_timer:  float  = 0.0
var _terminado:   bool   = false
var _passageiros: Array  = []   # pedestres NPC embarcados
var _pos_ant:     Vector2 = Vector2.ZERO
var _stuck_t:     float   = 0.0
const STUCK_DIST2 = 100.0
const STUCK_TEMPO = 6.0   # ônibus tolera mais tempo parado (pode estar em ponto)

signal chegou_ao_fim


func _ready() -> void:
	add_to_group("npc_onibus")
	collision_layer = 2
	collision_mask  = 1   # só colide com prédios; carros/ônibus não desviam a rota
	z_index = 5
	_criar_visual()
	_criar_colisao()


func _criar_visual() -> void:
	var tex = load(_TEX_PATH) if ResourceLoader.exists(_TEX_PATH) else null
	if tex:
		var sprite     = Sprite.new()
		sprite.texture = tex
		# SP_013.png: 44×83 px → scale 3.0 → 132×249 px no jogo
		sprite.scale   = Vector2(3.0, 3.0)
		add_child(sprite)
	else:
		var rect  = Polygon2D.new()
		rect.color = Color(0.85, 0.55, 0.10)
		rect.polygon = PoolVector2Array([
			Vector2(-45, -130), Vector2(45, -130),
			Vector2(45,  130),  Vector2(-45,  130),
		])
		add_child(rect)
		for i in range(-3, 4):
			var janela = Polygon2D.new()
			janela.color = Color(0.55, 0.75, 0.95, 0.8)
			var yc = i * 36.0
			janela.polygon = PoolVector2Array([
				Vector2(-32, yc - 12), Vector2(32, yc - 12),
				Vector2(32,  yc + 12), Vector2(-32, yc + 12),
			])
			add_child(janela)


func _criar_colisao() -> void:
	var shape = RectangleShape2D.new()
	# SP_013.png: 44×83 px × scale 3.0 → 132×249 → extents = metade
	shape.extents = Vector2(66.0, 124.0)
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func inicializar(wps: PoolVector2Array, paradas_idx: Array, start: int = 0) -> void:
	_liberar_todos_passageiros()
	_wps         = wps
	_paradas_idx = paradas_idx
	_idx         = start if start < wps.size() else wps.size() - 1
	if _idx < 0: _idx = 0
	_speed       = 0.0
	_estado      = Estado.DIRIGINDO
	_terminado   = false
	if _wps.size() > 0:
		position = _wps[_idx]
		if _idx + 1 < _wps.size():
			var dir = (_wps[_idx + 1] - _wps[_idx]).normalized()
			rotation = atan2(dir.y, dir.x) + PI * 0.5


func _physics_process(delta: float) -> void:
	match _estado:
		Estado.DIRIGINDO:      _tick_dirigindo(delta)
		Estado.FREANDO_PARADA: _tick_freando(delta)
		Estado.PARADO_PONTO:   _tick_parado(delta)


func _proximo_eh_parada() -> bool:
	return _paradas_idx.has(_idx)


func _tick_dirigindo(delta: float) -> void:
	if _idx >= _wps.size():
		if not _terminado:
			_terminado = true
			emit_signal("chegou_ao_fim")
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	if _proximo_eh_parada() and dist < DIST_INICIO_FREAR:
		_estado = Estado.FREANDO_PARADA
		return

	if dist < DIST_WP:
		_idx += 1
		return

	rotation = atan2(diff.y, diff.x) + PI * 0.5
	_speed   = move_toward(_speed, MAX_SPEED, ENGINE_POWER * delta)
	move_and_slide(-transform.y * _speed)

	# Despawn por travamento (ônibus fora da rota ou bloqueado)
	if position.distance_squared_to(_pos_ant) < STUCK_DIST2:
		_stuck_t += delta
		if _stuck_t >= STUCK_TEMPO:
			_stuck_t   = 0.0
			_terminado = true
			emit_signal("chegou_ao_fim")
	else:
		_stuck_t = 0.0
	_pos_ant = position


func _tick_freando(delta: float) -> void:
	if _idx >= _wps.size():
		_estado = Estado.DIRIGINDO
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	if dist < DIST_PARADO:
		_speed      = 0.0
		_estado     = Estado.PARADO_PONTO
		_wait_timer = lerp(ESPERA_PARADA_MIN, ESPERA_PARADA_MAX, randf())
		print("[Onibus] parada wp=%d  passageiros=%d  pos=%s" % [_idx, _passageiros.size(), position])
		_desembarcar()   # passageiros saem ao chegar na parada
		return

	rotation = atan2(diff.y, diff.x) + PI * 0.5
	_speed   = move_toward(_speed, 0.0, BRAKING_POWER * delta)
	if _speed > 2.0:
		move_and_slide(-transform.y * _speed)


func _tick_parado(delta: float) -> void:
	_wait_timer -= delta
	if _wait_timer <= 0.0:
		_embarcar()      # novos passageiros sobem antes de partir
		_idx   += 1
		_estado = Estado.DIRIGINDO


# ── Embarque ─────────────────────────────────────────────────────────────────

func _embarcar() -> void:
	var antes = _passageiros.size()
	if antes >= MAX_PASSAGEIROS:
		return
	for ped in get_tree().get_nodes_in_group("pedestres"):
		if not is_instance_valid(ped):
			continue
		if ped.get("_morto"):
			continue
		if position.distance_to(ped.position) > RAIO_EMBARQUE:
			continue
		if randf() > PROB_EMBARQUE:
			continue
		ped.visible             = false
		ped.set_physics_process(false)
		ped.collision_layer     = 0
		ped.collision_mask      = 0
		_passageiros.append(ped)
		if _passageiros.size() >= MAX_PASSAGEIROS:
			break
	if _passageiros.size() > antes:
		print("[Onibus] embarcaram %d  total=%d" % [_passageiros.size() - antes, _passageiros.size()])


# ── Desembarque ───────────────────────────────────────────────────────────────

func _desembarcar() -> void:
	var lado      = transform.x   # perpendicular ao ônibus
	var restantes = []
	for ped in _passageiros:
		if not is_instance_valid(ped):
			continue
		if randf() < PROB_DESEMBARQUE:
			var offset = lado * OFFSET_SAIDA * (1.0 if randi() % 2 == 0 else -1.0)
			ped.position        = position + offset
			ped.visible         = true
			ped.set_physics_process(true)
			ped.collision_layer = 8
			ped.collision_mask  = 1
		else:
			restantes.append(ped)
	_passageiros = restantes


func _liberar_todos_passageiros() -> void:
	for ped in _passageiros:
		if not is_instance_valid(ped):
			continue
		ped.position        = position
		ped.visible         = true
		ped.set_physics_process(true)
		ped.collision_layer = 8
		ped.collision_mask  = 1
	_passageiros = []
