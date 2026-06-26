# car.gd — Física arcade top-down (modelo bicicleta — Godot 3)
# Ref: kidscancode.org/godot_recipes/3.x/2d/car_steering/
extends KinematicBody2D

# ── Modelo bicicleta ────────────────────────────────────────────────────────
export var wheel_base:     float = 150.0   # distância entre eixos (px)
export var steering_angle: float = 22.0    # ângulo máximo de esterçamento (°)
export var engine_power:   float = 600.0   # aceleração (px/s²)
export var braking_power:  float = 900.0   # frenagem (px/s²)
export var friction_dec:   float = 300.0   # desaceleração por atrito (px/s²)
export var max_speed:      float = 1074.0
export var max_speed_re:   float = 260.0   # máximo em ré

# Atropelamento
const RAIO_ATROPELO    = 45.0
const VEL_ATROPELO_KMH = 70.0

# Batida / câmera
const FLASH_DURACAO = 0.30
const SHAKE_DECAY   = 80.0

# Marcas de pneu
const MAX_MARCAS     = 30
const LIMIAR_DERRAPA = 0.28          # |sin(ângulo heading×vel)| ≈ 16°
const PNEU_ESQ_LOCAL = Vector2(10,  150)
const PNEU_DIR_LOCAL = Vector2(62,  150)

var em_uso: bool = false setget _set_em_uso

# Estado físico
var _velocity:    Vector2 = Vector2.ZERO
var _speed:       float   = 0.0   # escalar com sinal (+ frente, − ré)
var _steer_angle: float   = 0.0

var _loader         = null
var _posicao_salva: float = 0.0
var _marcas:        Array = []
var _pneu_esq_ant         = null
var _pneu_dir_ant         = null
var _shake_ampl:    float = 0.0
var _flash_timer:   float = 0.0
var _col_cooldown:  Dictionary = {}

onready var _camera: Camera2D          = $Camera2D
onready var _radio:  AudioStreamPlayer = $Radio
onready var _visual: Polygon2D         = $Visual

const FAIXAS = [
	"res://assets/radio/radio1.mp3",
	"res://assets/radio/SLUS-00789_BIL001.mp3",
	"res://assets/radio/SLUS-00789_FRONTEND003.mp3",
]
var _faixa_atual: int = 0

signal velocidade_mudou(kmh)


func parar() -> void:
	_speed    = 0.0
	_velocity = Vector2.ZERO

func _ready() -> void:
	_radio.connect("finished", self, "_on_radio_finished")
	collision_layer = 2   # fora do mask=1 dos pedestres → sem solavanco no atropelamento
	collision_mask  = 3
	add_to_group("player_car")

func _set_em_uso(val: bool) -> void:
	em_uso = val
	if val:
		_iniciar_radio()
	else:
		_posicao_salva = _radio.get_playback_position() if _radio.playing else _posicao_salva
		_radio.stop()
		_loader = null

func _iniciar_radio() -> void:
	_radio.stop()
	_loader = ResourceLoader.load_interactive(FAIXAS[_faixa_atual])

func _on_radio_finished() -> void:
	_faixa_atual = (_faixa_atual + 1) % FAIXAS.size()
	_posicao_salva = 0.0
	_iniciar_radio()

func _unhandled_input(event: InputEvent) -> void:
	if not em_uso:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_TAB:
		_faixa_atual = (_faixa_atual + 1) % FAIXAS.size()
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


# ── Entrada ─────────────────────────────────────────────────────────────────

func _get_input(delta: float) -> void:
	var throttle:   float = 0.0
	var steer_dir:  float = 0.0

	if Input.is_action_pressed("acelerar") or Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W): throttle  =  1.0
	elif Input.is_action_pressed("frear")  or Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S): throttle  = -1.0

	if Input.is_action_pressed("virar_direita") or Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): steer_dir =  1.0
	elif Input.is_action_pressed("virar_esquerda") or Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A): steer_dir = -1.0

	# ── Velocidade escalar (move_toward = feel arcade preservado) ────────────
	if throttle > 0.0:
		_speed = move_toward(_speed,  max_speed,    engine_power  * throttle * delta)
	elif throttle < 0.0:
		if _speed > 10.0:   # frente → frear
			_speed = move_toward(_speed, 0.0, braking_power * abs(throttle) * delta)
		else:               # parado ou em ré
			_speed = move_toward(_speed, -max_speed_re, engine_power * abs(throttle) * delta)
	else:
		_speed = move_toward(_speed, 0.0, friction_dec * delta)

	# ── Esterçamento: inversão automática em ré ──────────────────────────────
	var steer = steer_dir * deg2rad(steering_angle)
	if _speed < 0.0:
		steer = -steer
	_steer_angle = steer


# ── Modelo bicicleta ─────────────────────────────────────────────────────────
# Calcula nova direção e rotação a partir das posições das rodas.
# Funciona para frente e ré sem degenerar.

func _calculate_steering(delta: float) -> void:
	if abs(_speed) < 1.0:
		_velocity = Vector2.ZERO
		return

	var fwd         = -transform.y * _speed          # vetor de deslocamento
	var rear_wheel  = position + transform.y * (wheel_base / 2.0)
	var front_wheel = position - transform.y * (wheel_base / 2.0)
	rear_wheel  += fwd * delta
	front_wheel += fwd.rotated(_steer_angle) * delta

	var new_heading = (front_wheel - rear_wheel).normalized()
	if new_heading == Vector2.ZERO:
		return

	rotation  = atan2(new_heading.y, new_heading.x) + PI / 2.0
	_velocity = new_heading * _speed


# ── Loop principal ───────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not em_uso:
		_pneu_esq_ant = null
		_pneu_dir_ant = null
		_speed    = move_toward(_speed, 0.0, friction_dec * delta)
		_velocity = -transform.y * _speed
		_velocity = move_and_slide(_velocity)
		return

	_get_input(delta)
	_calculate_steering(delta)

	_velocity = move_and_slide(_velocity)

	# ── Cooldowns de colisão ─────────────────────────────────────────────────
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

	# ── Batida com carros NPC ────────────────────────────────────────────────
	if abs(_speed) > 80.0:
		for i in get_slide_count():
			var col = get_slide_collision(i)
			if col == null or col.collider == null:
				continue
			if not col.collider.is_in_group("npc_carros"):
				continue
			if _col_cooldown.has(col.collider):
				continue
			var impact = abs(_speed)
			col.collider.receber_impacto(-col.normal * impact * 0.70)
			_speed      *= 0.50
			_shake_ampl  = clamp(impact * 0.014, 5.0, 24.0)
			_flash_timer = FLASH_DURACAO
			_col_cooldown[col.collider] = 0.40
			break

	# ── Atropelamento ────────────────────────────────────────────────────────
	var kmh = abs(_speed) * 0.131
	if kmh > VEL_ATROPELO_KMH:
		for ped in get_tree().get_nodes_in_group("pedestres"):
			if is_instance_valid(ped) and not ped._morto:
				if position.distance_to(ped.position) < RAIO_ATROPELO:
					ped.atropelar()
					get_tree().call_group("hud", "registrar_atropelamento")
					_shake_ampl  = clamp(kmh * 0.12, 5.0, 18.0)
					_flash_timer = FLASH_DURACAO

	# ── Marcas de pneu ───────────────────────────────────────────────────────
	var pneu_esq = to_global(PNEU_ESQ_LOCAL)
	var pneu_dir = to_global(PNEU_DIR_LOCAL)
	var derrapa  = false
	if abs(_speed) > 100.0 and _velocity.length() > 10.0:
		var heading = -transform.y
		derrapa = abs(heading.cross(_velocity.normalized())) > LIMIAR_DERRAPA

	if _pneu_esq_ant != null and derrapa:
		_adicionar_marca(_pneu_esq_ant, pneu_esq)
		_adicionar_marca(_pneu_dir_ant, pneu_dir)

	_pneu_esq_ant = pneu_esq
	_pneu_dir_ant = pneu_dir

	# ── Camera shake ─────────────────────────────────────────────────────────
	if _shake_ampl > 0.1:
		_camera.offset = Vector2(
			(randf() * 2.0 - 1.0) * _shake_ampl,
			(randf() * 2.0 - 1.0) * _shake_ampl)
		_shake_ampl = move_toward(_shake_ampl, 0.0, SHAKE_DECAY * delta)
	else:
		_camera.offset = Vector2.ZERO

	# ── Flash de impacto ─────────────────────────────────────────────────────
	if _flash_timer > 0.0:
		_flash_timer -= delta
		var t = clamp(_flash_timer / FLASH_DURACAO, 0.0, 1.0)
		_visual.modulate = Color(1.0 + t * 0.5, 1.0 - t * 0.4, 1.0 - t * 0.4)
	else:
		_visual.modulate = Color(1, 1, 1)

	# ── Zoom dinâmico ────────────────────────────────────────────────────────
	var fator = clamp(abs(_speed) / max_speed, 0.0, 1.0)
	var zoom_alvo: float = lerp(1.4, 2.2, fator)
	_camera.zoom = lerp(_camera.zoom, Vector2(zoom_alvo, zoom_alvo), 4.0 * delta)

	emit_signal("velocidade_mudou", abs(_speed) * 0.131)


func receber_impacto_externo(impulso: Vector2) -> void:
	if not em_uso:
		return
	var fwd      = -transform.y
	_speed      += impulso.dot(fwd) * 0.40
	_speed       = clamp(_speed, -max_speed_re, max_speed)
	_shake_ampl  = clamp(impulso.length() * 0.010, 2.0, 12.0)
	_flash_timer = FLASH_DURACAO * 0.5


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
