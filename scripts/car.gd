# car.gd — Física arcade top-down (Godot 3)
extends KinematicBody2D

export var wheel_base:     float = 95.0
export var steering_angle: float = 29.0   # ângulo máximo das rodas (°)
export var engine_power:   float = 800.0
export var braking:        float = 450.0
export var friction:       float = -49.0
export var drag:           float = -0.01
export var max_speed_re:   float = 950.0
export var max_speed:      float = 774.0  # referência para câmera/HUD

export var drift_grip_normal: float = 5.0   # grip padrão (menor = desliza mais)
export var drift_grip_drift:  float = 1.1   # grip no freio de mão (drift)

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

const RAIO_ATROPELO    = 35.0
const VEL_ATROPELO_KMH = 20.0
const FLASH_DURACAO    = 0.30
const SHAKE_DECAY      = 80.0
const LOOK_AHEAD       = 350.0
const LOOK_AHEAD_VEL   = 1.5
const BASE_CAM_LOCAL   = Vector2(37.5, -120.0)
const MAX_MARCAS       = 160
const LIMIAR_DERRAPA   = 80.0
const PNEU_TR_ESQ_LOCAL = Vector2(10, 150) # Traseiro Esquerdo
const PNEU_TR_DIR_LOCAL = Vector2(62, 150) # Traseiro Direito
const PNEU_DI_ESQ_LOCAL = Vector2(10, 55)  # Dianteiro Esquerdo
const PNEU_DI_DIR_LOCAL = Vector2(62, 55)  # Dianteiro Direito

var em_uso: bool = false setget _set_em_uso

var _velocity:     Vector2 = Vector2.ZERO
var _acceleration: Vector2 = Vector2.ZERO
var _steer_dir:    float   = 0.0
var _speed:        float   = 0.0
var _lat_vel:      Vector2 = Vector2.ZERO

var _loader             = null
var _marcas:        Array = []
var _pneu_tr_esq_ant      = null
var _pneu_tr_dir_ant      = null
var _pneu_di_esq_ant      = null
var _pneu_di_dir_ant      = null
var _shake_ampl:        float   = 0.0
var _flash_timer:       float   = 0.0
var _look_ahead_offset: Vector2 = Vector2.ZERO
var _prev_position:     Vector2 = Vector2.ZERO
var _col_cooldown:      Dictionary = {}
var _joy                           = null
var _gear_atual:        int     = 1
var _shift_timer:       float   = 0.0

onready var _camera: Camera2D          = $Camera2D
onready var _radio:  AudioStreamPlayer = $Radio
onready var _visual: Polygon2D         = $Visual
onready var _sombra: Polygon2D         = $Sombra

const FAIXAS = [
	"res://assets/radio/radio1.mp3",
	"res://assets/radio/SLUS-00789_BIL001.mp3",
	"res://assets/radio/SLUS-00789_FRONTEND003.mp3",
]
var _faixa_atual: int = 0

signal velocidade_mudou(kmh, marcha)


func parar() -> void:
	_velocity = Vector2.ZERO
	_speed    = 0.0

func _ready() -> void:
	scale = Vector2(0.97, 0.97)
	_radio.connect("finished", self, "_on_radio_finished")
	aplicar_modelo(0, Color(0.99, 1.0, 0.0))
	collision_layer = 2
	collision_mask  = 3
	add_to_group("player_car")

func _set_em_uso(val: bool) -> void:
	em_uso = val
	if val:
		_faixa_atual = randi() % FAIXAS.size()
		_iniciar_radio()
	else:
		_radio.stop()
		_loader = null

func _iniciar_radio() -> void:
	_radio.stop()
	_loader = ResourceLoader.load_interactive(FAIXAS[_faixa_atual])

func _on_radio_finished() -> void:
	_faixa_atual = _proxima_faixa_aleatoria()
	_iniciar_radio()

func _proxima_faixa_aleatoria() -> int:
	if FAIXAS.size() <= 1:
		return 0
	var nova = randi() % FAIXAS.size()
	if nova == _faixa_atual:
		nova = (nova + 1) % FAIXAS.size()
	return nova

func _unhandled_input(event: InputEvent) -> void:
	if not em_uso:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_TAB:
		_faixa_atual = _proxima_faixa_aleatoria()
		_iniciar_radio()

func _process(_delta: float) -> void:
	if _loader == null or not em_uso:
		return
	var err = _loader.poll()
	if err == ERR_FILE_EOF:
		_radio.stream = _loader.get_resource()
		_radio.play()
		_loader = null
	elif err != OK:
		_loader = null


func _get_joystick():
	if _joy == null or not is_instance_valid(_joy):
		var nos = get_tree().get_nodes_in_group("virtual_joystick")
		_joy = nos[0] if not nos.empty() else null
	return _joy


func _get_current_engine_power() -> float:
	if _shift_timer > 0.0:
		return engine_power * 0.05  # Corte de embreagem durante a troca de marcha

	var speed = _velocity.length()
	var speed_ratio = clamp(speed / max_speed, 0.0, 1.0)
	var gear_mult = 1.0
	
	if speed_ratio < 0.35:
		gear_mult = 1.25  # 1ª Marcha: Arrancada forte
	elif speed_ratio < 0.70:
		gear_mult = 0.85  # 2ª Marcha: Média
	else:
		gear_mult = 0.55  # 3ª Marcha: Aceleração final progressiva
		
	return engine_power * gear_mult


func _get_input() -> void:
	var steer_dir: float = 0.0
	
	# Lê joystick analógico se estiver ativo (Mobile)
	var joy = _get_joystick()
	if joy != null and joy.visible and joy.output.length() > joy.dead_zone:
		steer_dir = joy.output.x
	else:
		# Teclado / Ações digitais
		if   Input.is_action_pressed("virar_direita")  or Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): steer_dir =  1.0
		elif Input.is_action_pressed("virar_esquerda") or Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): steer_dir = -1.0
		
	_steer_dir = steer_dir * deg2rad(steering_angle)

	_acceleration = Vector2.ZERO
	var acelerando = Input.is_action_pressed("acelerar") or Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W)
	var freando = Input.is_action_pressed("frear") or Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)

	if Input.is_key_pressed(KEY_SPACE):
		var current_speed = _velocity.dot(-transform.y)
		if current_speed > 15.0:
			_acceleration = -transform.y * (-braking * 2.5) # Freia o movimento frontal
		elif current_speed < -15.0:
			_acceleration = -transform.y * (braking * 2.5)  # Freia o movimento de ré
		elif not acelerando:
			_velocity = Vector2.ZERO # Só trava parado se não estiver tentando acelerar
		
		# Se acelerar enquanto puxa o freio de mão, aplica torque do motor para girar e dar cavalo de pau!
		if acelerando:
			_acceleration += -transform.y * _get_current_engine_power() * 1.1
	else:
		if acelerando:
			_acceleration = -transform.y * _get_current_engine_power()
		elif freando:
			_acceleration = -transform.y * (-braking)


func _apply_friction(delta: float) -> void:
	if _acceleration == Vector2.ZERO and _velocity.length() < 50.0:
		_velocity = Vector2.ZERO
		return
	_acceleration += _velocity * friction * delta
	_acceleration += _velocity * _velocity.length() * drag * delta


func _calculate_steering(delta: float) -> void:
	if _velocity.length() < 1.0:
		return

	# O grip físico em condução normal é extremamente alto (estilo trilho de trem) para garantir curvas estáveis de raio constante
	var vel_rel = clamp(_velocity.length() / max_speed, 0.0, 1.0)
	var base_grip = drift_grip_normal * 6.0  # Multiplica o grip base para travar a trajetória cinemática
	var grip_atual = lerp(base_grip * 1.5, base_grip, vel_rel)

	# Se pressionar ESPAÇO (freio de mão), o grip cai drasticamente para iniciar o drift/derrapagem
	if Input.is_key_pressed(KEY_SPACE):
		grip_atual = drift_grip_drift

	# Rotação física baseada na velocidade do carro e ângulo de esterço (geometria real)
	var forward_dir = -transform.y
	var speed = _velocity.length()
	
	# Taxa de rotação cinemática padrão: w = v * steer / L (evita o efeito ponteiro de relógio em baixa velocidade)
	var turn_speed = speed * _steer_dir / wheel_base

	var acelerando = Input.is_action_pressed("acelerar") or Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up")

	# Sobrescrita para freio de mão e derrapagens (sobre-esterço arcade)
	if Input.is_key_pressed(KEY_SPACE):
		if acelerando:
			# Cavalo de pau / Donut: rotação rápida que escala com a velocidade para não girar parado
			var pivot_scale = clamp(speed / 90.0, 0.0, 1.0)
			turn_speed = _steer_dir * 8.0 * pivot_scale
		else:
			# Deslizamento lateral com freio de mão (traseira escorregando rápido)
			turn_speed *= 2.8
	else:
		# Derrapagem natural em alta velocidade: aumenta a rotação à medida que o carro desliza lateralmente
		var lateral_speed = (_velocity - forward_dir * _velocity.dot(forward_dir)).length()
		var slip_factor = clamp(lateral_speed / 120.0, 0.0, 1.0)
		turn_speed *= lerp(1.0, 2.4, slip_factor)

	# Inverte a rotação se o carro estiver andando de ré
	if _velocity.dot(forward_dir) < 0.0:
		turn_speed = -turn_speed

	# Aplica a rotação diretamente no próprio centro (eixo) do carro
	rotation += turn_speed * delta
	var target_vel = forward_dir * _velocity.length()
	var original_speed = _velocity.length()

	# Determina se está indo para frente ou de ré
	var d = forward_dir.dot(_velocity.normalized())

	if d >= 0:
		_velocity = _velocity.linear_interpolate(target_vel, grip_atual * delta)
	else:
		_velocity = _velocity.linear_interpolate(-forward_dir * min(_velocity.length(), max_speed_re), grip_atual * delta)

	# Atrito de derrapagem (perda de velocidade por arrasto lateral)
	if _velocity.length() > 0.1:
		var lateral_speed = (_velocity - forward_dir * _velocity.dot(forward_dir)).length()
		
		# A perda de velocidade aumenta com a intensidade da derrapagem (velocidade lateral)
		# Se usar freio de mão (SPACE), simula o travamento das rodas com atrito ainda maior
		var drift_friction_coeff = 0.65  # Coeficiente de arrasto de derrapagem base
		if Input.is_key_pressed(KEY_SPACE):
			drift_friction_coeff = 1.05  # Arrasto intenso ao travar as rodas com freio de mão
			
		var speed_loss = lateral_speed * drift_friction_coeff * delta
		var final_speed = max(0.0, original_speed - speed_loss)
		
		_velocity = _velocity.normalized() * final_speed


func _physics_process(delta: float) -> void:
	if _shift_timer > 0.0:
		_shift_timer = max(0.0, _shift_timer - delta)

	if not em_uso:
		_pneu_tr_esq_ant = null
		_pneu_tr_dir_ant = null
		_pneu_di_esq_ant = null
		_pneu_di_dir_ant = null
		_velocity    *= pow(0.3, delta)
		if _velocity.length() < 10.0:
			_velocity = Vector2.ZERO
		_velocity = move_and_slide(_velocity)
		return

	_get_input()
	_apply_friction(delta)
	_calculate_steering(delta)
	_prev_position = position
	_velocity += _acceleration * delta
	_velocity  = move_and_slide(_velocity)
	_speed     = _velocity.dot(-transform.y)

	var heading = -transform.y
	_lat_vel    = _velocity - heading * _velocity.dot(heading)

	# ── Cooldowns de colisão ──────────────────────────────────────────────────
	var _remover = []
	for key in _col_cooldown.keys():
		if not is_instance_valid(key):
			_remover.append(key)
			continue
		_col_cooldown[key] -= delta
		if _col_cooldown[key] <= 0.0:
			_remover.append(key)
	for key in _remover:
		_col_cooldown.erase(key)

	# ── Batida com carros NPC ─────────────────────────────────────────────────
	if _velocity.length() > 80.0:
		for i in get_slide_count():
			var col = get_slide_collision(i)
			if col == null or col.collider == null:
				continue
			if not col.collider.is_in_group("npc_carros"):
				continue
			if _col_cooldown.has(col.collider):
				continue
			var impact = _velocity.length()
			col.collider.receber_impacto(-col.normal * impact * 0.70)
			_velocity   *= 0.50
			_shake_ampl  = clamp(impact * 0.014, 5.0, 24.0)
			_flash_timer = FLASH_DURACAO
			_col_cooldown[col.collider] = 0.40
			Input.vibrate_handheld(clamp(int(impact * 0.15), 60, 400))
			break

	# ── Atropelamento ─────────────────────────────────────────────────────────
	var kmh = _velocity.length() * 0.131
	if kmh > VEL_ATROPELO_KMH:
		for ped in get_tree().get_nodes_in_group("pedestres"):
			if is_instance_valid(ped) and not ped._morto:
				if _ped_dentro_carro(ped.position):
					ped.atropelar()
					get_tree().call_group("hud", "registrar_atropelamento")
					_shake_ampl  = clamp(kmh * 0.12, 5.0, 18.0)
					_flash_timer = FLASH_DURACAO
					Input.vibrate_handheld(120)

	# ── Marcas de pneu ────────────────────────────────────────────────────────
	var pneu_tr_esq = transform.xform(PNEU_TR_ESQ_LOCAL)
	var pneu_tr_dir = transform.xform(PNEU_TR_DIR_LOCAL)
	var pneu_di_esq = transform.xform(PNEU_DI_ESQ_LOCAL)
	var pneu_di_dir = transform.xform(PNEU_DI_DIR_LOCAL)
	
	if _pneu_tr_esq_ant != null and _lat_vel.length() > LIMIAR_DERRAPA and _velocity.length() > 100.0:
		_adicionar_marca(_pneu_tr_esq_ant, pneu_tr_esq)
		_adicionar_marca(_pneu_tr_dir_ant, pneu_tr_dir)
		_adicionar_marca(_pneu_di_esq_ant, pneu_di_esq)
		_adicionar_marca(_pneu_di_dir_ant, pneu_di_dir)
		
	_pneu_tr_esq_ant = pneu_tr_esq
	_pneu_tr_dir_ant = pneu_tr_dir
	_pneu_di_esq_ant = pneu_di_esq
	_pneu_di_dir_ant = pneu_di_dir

	# ── Câmera Ancorada (para análise precisa da curva) ──────────────────────
	_camera.position = Vector2.ZERO
	_camera.offset   = Vector2.ZERO
	_camera.zoom     = Vector2(1.5, 1.5)

	# ── Flash de impacto ──────────────────────────────────────────────────────
	if _flash_timer > 0.0:
		_flash_timer -= delta
		var t = clamp(_flash_timer / FLASH_DURACAO, 0.0, 1.0)
		_visual.modulate = Color(1.0 + t*0.5, 1.0 - t*0.4, 1.0 - t*0.4)
	else:
		_visual.modulate = Color(1, 1, 1)

	# ── Atualiza a Sombra para manter o ângulo fixo global ───────────────────
	if _sombra:
		_sombra.position = _visual.position + Vector2(5.0, 5.0).rotated(-rotation)

	# Atualização de marchas e embreagem (shift) com Histerese (evita oscilação)
	var nova_marcha = _gear_atual
	if _velocity.length() < 15.0:
		nova_marcha = 0 # N
	elif _velocity.dot(heading) < -15.0:
		nova_marcha = -1 # R
	else:
		var speed_ratio = clamp(_velocity.length() / max_speed, 0.0, 1.0)
		if _gear_atual <= 0:
			nova_marcha = 1
		elif _gear_atual == 1:
			if speed_ratio >= 0.35:
				nova_marcha = 2
		elif _gear_atual == 2:
			if speed_ratio >= 0.70:
				nova_marcha = 3
			elif speed_ratio < 0.28:
				nova_marcha = 1
		elif _gear_atual == 3:
			if speed_ratio < 0.62:
				nova_marcha = 2

	# Só activa o shift timer se mudar de marcha em movimento para frente
	if nova_marcha != _gear_atual:
		if _gear_atual > 0 and nova_marcha > 0:
			_shift_timer = 0.16 # 160ms de corte de torque
		_gear_atual = nova_marcha

	emit_signal("velocidade_mudou", _velocity.length() * 0.131, _gear_atual)


func receber_impacto_externo(impulso: Vector2) -> void:
	if not em_uso:
		return
	_velocity   += impulso * 0.40
	_shake_ampl  = clamp(impulso.length() * 0.010, 2.0, 12.0)
	_flash_timer = FLASH_DURACAO * 0.5


func _ped_dentro_carro(ped_pos: Vector2) -> bool:
	# Converte para espaço local do carro → checa retângulo orientado
	# CollisionShape2D center=(37.5, 82.2), extents=(32, 61) + margem
	var rel := to_local(ped_pos) - Vector2(37.5, 82.0)
	return abs(rel.x) < 38.0 and abs(rel.y) < 68.0


func _adicionar_marca(p1: Vector2, p2: Vector2) -> void:
	if p1.distance_squared_to(p2) < 4.0:
		return
	var linha = Line2D.new()
	linha.add_point(p1)
	linha.add_point(p2)
	linha.width         = 7.0
	linha.default_color = Color(0.07, 0.07, 0.07, 0.80)
	linha.z_index       = -5
	get_parent().add_child(linha)
	_marcas.append(linha)
	while _marcas.size() > MAX_MARCAS:
		var antiga = _marcas.pop_front()
		if is_instance_valid(antiga):
			antiga.queue_free()


func aplicar_modelo(modelo_idx: int, cor: Color) -> void:
	var modelo = MODELOS[modelo_idx]
	engine_power = modelo["engine_power"]
	braking = modelo["braking"]
	max_speed = modelo["max_speed"]
	drift_grip_normal = modelo["grip_normal"]
	drift_grip_drift = modelo["grip_drift"]
	
	var visual = get_node_or_null("Visual")
	if visual:
		visual.texture = modelo["textura"]
		visual.color = cor
