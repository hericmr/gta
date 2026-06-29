# npc_onibus.gd — Ônibus NPC que segue rotas reais de Santos (Godot 3)
extends KinematicBody2D

# Física do ônibus: mais lento, aceleração/frenagem suaves, maior inércia
const MAX_SPEED       = 1060.0
const ENGINE_POWER    = 140.0
const BRAKING_POWER   = 110.0

# Thresholds de waypoint / parada
const DIST_WP           = 80.0
const DIST_PARADO       = 180.0   # raio generoso: GPS não é preciso ao metro
const ESPERA_PARADA_MIN = 3.0
const ESPERA_PARADA_MAX = 6.0

# Embarque / desembarque
const RAIO_EMBARQUE    = 240.0   # raio para embarcar pedestres
const RAIO_CHAMADA     = 650.0   # raio para chamar pedestres esperando no ponto
const MAX_PASSAGEIROS  = 50      # lotação máxima
const PROB_EMBARQUE    = 0.90    # chance de um pedestre próximo embarcar
const PROB_DESEMBARQUE = 0.65    # chance de desembarcar em cada parada
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
var _passageiros:  Array   = []
var _pos_check:    Vector2 = Vector2.ZERO   # posição amostrada periodicamente
var _check_timer:  float   = 0.0
var _stuck_t:      float   = 0.0
var _fator_tick:   int     = 0
var _fator_cache:  float   = 1.0
var _sensor_peds:  Area2D  = null
const STUCK_INTERVALO  = 3.0      # amostra posição a cada 3 s
const STUCK_MIN_DIST   = 200.0    # deve mover ao menos 200 px em 3 s para não ser stuck
const STUCK_LIMITE     = 9.0      # após 9 s parado → despawn (3 intervalos)

var _visual:      Node2D = null
var _sombra:      Node2D = null

signal chegou_ao_fim


func _ready() -> void:
	add_to_group("npc_onibus")
	collision_layer = 2
	collision_mask  = 1   # só colide com prédios; carros/ônibus não desviam a rota
	z_index = 5
	_criar_visual()
	_criar_colisao()

	# Cria o sensor físico de pedestres (otimizado no C++ do motor)
	_sensor_peds = Area2D.new()
	_sensor_peds.collision_layer = 0
	_sensor_peds.collision_mask  = 8 # Camada 4: Pedestres e Player
	var s_shape = RectangleShape2D.new()
	s_shape.extents = Vector2(33.0, 73.0) # Proporcional ao novo tamanho do ônibus
	var s_col = CollisionShape2D.new()
	s_col.shape = s_shape
	s_col.position = Vector2(0.0, -156.0) # Centralizado em frente ao parachoque dianteiro
	_sensor_peds.add_child(s_col)
	add_child(_sensor_peds)


func _criar_visual() -> void:
	var tex = load(_TEX_PATH) if ResourceLoader.exists(_TEX_PATH) else null
	if tex:
		# Sombra
		_sombra = Sprite.new()
		_sombra.name = "Sombra"
		_sombra.texture = tex
		_sombra.scale   = Vector2(2.0, 2.0) # Escala unificada 2x
		_sombra.modulate = Color(0.0, 0.0, 0.0, 0.4)
		_sombra.position = Vector2(5.0, 5.0)
		_sombra.z_index = -1
		add_child(_sombra)

		# Visual
		_visual = Sprite.new()
		_visual.name = "Visual"
		_visual.texture = tex
		_visual.scale   = Vector2(2.0, 2.0) # Escala unificada 2x
		add_child(_visual)
	else:
		# Sombra
		var shadow_poly = Polygon2D.new()
		shadow_poly.name = "Sombra"
		shadow_poly.polygon = PoolVector2Array([
			Vector2(-30, -83), Vector2(30, -83),
			Vector2(30,  83),  Vector2(-30,  83),
		])
		shadow_poly.color = Color(0.0, 0.0, 0.0, 0.4)
		shadow_poly.position = Vector2(5.0, 5.0)
		shadow_poly.z_index = -1
		_sombra = shadow_poly
		add_child(_sombra)

		# Visual
		var rect  = Polygon2D.new()
		rect.name = "Visual"
		rect.color = Color(0.85, 0.55, 0.10)
		rect.polygon = PoolVector2Array([
			Vector2(-30, -83), Vector2(30, -83),
			Vector2(30,  83),  Vector2(-30,  83),
		])
		_visual = rect
		add_child(_visual)
		
		for i in range(-3, 4):
			var janela = Polygon2D.new()
			janela.color = Color(0.55, 0.75, 0.95, 0.8)
			var yc = i * 24.0
			janela.polygon = PoolVector2Array([
				Vector2(-21, yc - 8), Vector2(21, yc - 8),
				Vector2(21,  yc + 8), Vector2(-21, yc + 8),
			])
			add_child(janela)


func _criar_colisao() -> void:
	var shape = RectangleShape2D.new()
	# SP_013.png: 44×83 px × scale 2.0 → 88×166 → extents = metade (44x83)
	shape.extents = Vector2(44.0, 83.0)
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

	if _sombra and _visual:
		_sombra.position = _visual.position + Vector2(5.0, 5.0).rotated(-rotation)


func _proximo_eh_parada() -> bool:
	return _paradas_idx.has(_idx)


func _verificar_stuck(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= STUCK_INTERVALO:
		var moveu = position.distance_to(_pos_check)
		if moveu < STUCK_MIN_DIST:
			_stuck_t += STUCK_INTERVALO
			if _stuck_t >= STUCK_LIMITE:
				_stuck_t = 0.0
				_terminado = true
				emit_signal("chegou_ao_fim")
		else:
			_stuck_t = 0.0
		_pos_check   = position
		_check_timer = 0.0


func _tick_dirigindo(delta: float) -> void:
	if _idx >= _wps.size():
		if not _terminado:
			_terminado = true
			emit_signal("chegou_ao_fim")
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	# Distância de frenagem dinâmica baseada na velocidade física real + margem
	var braking_dist = (_speed * _speed) / (2.0 * BRAKING_POWER) + 250.0
	if _proximo_eh_parada() and dist < braking_dist:
		_estado = Estado.FREANDO_PARADA
		return

	if dist < DIST_WP:
		_idx += 1
		return

	rotation = atan2(diff.y, diff.x) + PI * 0.5
	var proximity_factor = _fator_proximidade()
	var target_vel = MAX_SPEED * proximity_factor
	_speed   = move_toward(_speed, target_vel, (BRAKING_POWER * 2.0 if proximity_factor < 0.2 else ENGINE_POWER) * delta)
	move_and_slide(-transform.y * _speed)

	_verificar_stuck(delta)


func _tick_freando(delta: float) -> void:
	if _idx >= _wps.size():
		_estado = Estado.DIRIGINDO
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	rotation = atan2(diff.y, diff.x) + PI * 0.5
	
	# Desaceleração física progressiva em direção ao ponto
	var target_vel = sqrt(2.0 * BRAKING_POWER * max(0.0, dist - 30.0))
	var proximity_factor = _fator_proximidade()
	target_vel = min(target_vel, MAX_SPEED * proximity_factor)
	_speed = move_toward(_speed, target_vel, (BRAKING_POWER * 2.0 if proximity_factor < 0.2 else BRAKING_POWER) * delta)
	
	if _speed > 2.0:
		move_and_slide(-transform.y * _speed)

	# Chega à parada SOMENTE se estiver dentro do raio de parada real (sem falsos positivos por tráfego)
	if dist < DIST_PARADO:
		_speed      = 0.0
		_estado     = Estado.PARADO_PONTO
		_wait_timer = lerp(ESPERA_PARADA_MIN, ESPERA_PARADA_MAX, randf())
		_desembarcar()
		_chamar_pedestres()

	_verificar_stuck(delta)


func _tick_parado(delta: float) -> void:
	_pos_check   = position   # evita stuck-detection ao retomar movimento
	_check_timer = 0.0
	_stuck_t     = 0.0

	# Tenta embarcar pedestres que chegarem perto a cada frame
	_embarcar()

	_wait_timer -= delta
	if _wait_timer <= 0.0:
		# Verifica se ainda há algum pedestre próximo vindo em direção ao ônibus
		var alguem_vindo = false
		for ped in get_tree().get_nodes_in_group("pedestres"):
			if is_instance_valid(ped) and not ped._morto:
				if not ped._esperando_onibus and global_position.distance_to(ped.global_position) < 380.0:
					alguem_vindo = true
					break
		
		# Estende a espera por até 3 segundos adicionais se houver pedestres a caminho
		if alguem_vindo and _wait_timer > -3.0:
			return

		_idx   += 1
		_estado = Estado.DIRIGINDO


# ── Emplaque ─────────────────────────────────────────────────────────────────

func _chamar_pedestres() -> void:
	for ped in get_tree().get_nodes_in_group("pedestres"):
		if not is_instance_valid(ped) or ped._morto:
			continue
		if not ped._esperando_onibus:
			continue
		if global_position.distance_to(ped.global_position) > RAIO_CHAMADA:
			continue
		ped.caminhar_para(global_position)


func _embarcar() -> void:
	var antes = _passageiros.size()
	if antes >= MAX_PASSAGEIROS:
		return
	for ped in get_tree().get_nodes_in_group("pedestres"):
		if not is_instance_valid(ped):
			continue
		if ped._morto:
			continue
		if global_position.distance_to(ped.global_position) > RAIO_EMBARQUE:
			continue
		if randf() > PROB_EMBARQUE:
			continue
		ped.visible             = false
		ped.set_physics_process(false)
		ped.collision_layer     = 0
		ped.collision_mask      = 0
		ped.no_onibus           = true
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
			ped.no_onibus       = false
			ped.recem_desembarcado = true
			ped.emit_signal("chegou_ao_fim")
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
		ped.no_onibus       = false
		ped.emit_signal("chegou_ao_fim")
	_passageiros = []


# ── Detecção de Proximidade e Prevenção de Atropelamento ──────────────────────

func _fator_proximidade() -> float:
	_fator_tick = (_fator_tick + 1) % 3
	if _fator_tick != 0:
		return _fator_cache

	var fwd = -transform.y
	var melhor: float = 1.0

	# 1. Busca todos os tipos de veículos para evitar colisões
	var outros = get_tree().get_nodes_in_group("npc_carros") + \
				 get_tree().get_nodes_in_group("npc_onibus") + \
				 get_tree().get_nodes_in_group("player_car")

	for outro in outros:
		if outro == self or not is_instance_valid(outro):
			continue

		var delta_pos = outro.position - position
		var dist = delta_pos.length()

		var half_len_outro = 58.0
		if outro.is_in_group("npc_onibus"):
			half_len_outro = 83.0
		elif outro.is_in_group("player_car"):
			half_len_outro = 61.0

		var dist_min = 83.0 + half_len_outro + 27.0
		var dist_max = dist_min + 250.0

		if dist > dist_max:
			continue
		if fwd.dot(delta_pos / dist) < 0.92: # Cone de visão à frente
			continue

		var f = (dist - dist_min) / (dist_max - dist_min)
		if f < melhor:
			melhor = f

	# 2. Evita atropelamento de pedestres e do Player a pé usando Area2D (O(1) no script)
	if is_instance_valid(_sensor_peds):
		for ped in _sensor_peds.get_overlapping_bodies():
			if not is_instance_valid(ped) or ped.get("no_onibus") or ped.get("_morto"):
				continue

			var delta_pos = ped.position - position
			var dist = delta_pos.length()

			var dist_min = 83.0 + 10.0 + 27.0  # 83px (ônibus) + 10px (pedestre) + 27px margem
			var dist_max = dist_min + 180.0

			var f = (dist - dist_min) / (dist_max - dist_min)
			if f < melhor:
				melhor = f

	_fator_cache = clamp(melhor, 0.0, 1.0)
	return _fator_cache
