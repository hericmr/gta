# car.gd — Física arcade do carro top-down (KinematicBody2D — Godot 3)
extends KinematicBody2D

export var velocidade_maxima: float  = 1374.0
export var aceleracao: float         = 400.0
export var atrito: float             = 300.0
export var frenagem: float           = 900.0
export var velocidade_re: float      = 0.4

# Derrapagem
const ATRITO_LATERAL   = 380.0
const MAX_VEL_LATERAL  = 280.0
const LIMIAR_DERRAPA   = 20.0
const MAX_MARCAS       = 100
const PNEU_ESQ_LOCAL   = Vector2(10, 150)
const PNEU_DIR_LOCAL   = Vector2(62, 150)

# Atropelamento: raio de detecção e limiar de velocidade (km/h)
const RAIO_ATROPELO    = 45.0
const VEL_ATROPELO_KMH = 60.0

# Batida entre carros
const FLASH_DURACAO    = 0.30
const SHAKE_DECAY      = 80.0

var em_uso: bool        = false setget _set_em_uso
var _vel: float         = 0.0
var _vel_lateral: float = 0.0
var _loader             = null
var _posicao_salva: float = 0.0
var _marcas: Array      = []
var _pneu_esq_ant       = null   # Vector2 | null
var _pneu_dir_ant       = null

var _shake_ampl:   float      = 0.0
var _flash_timer:  float      = 0.0
var _col_cooldown: Dictionary = {}

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
	_vel         = 0.0
	_vel_lateral = 0.0

func _ready() -> void:
	_radio.connect("finished", self, "_on_radio_finished")
	collision_mask = 3   # layer 1 (prédios/chão) + layer 2 (carros NPC)
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

func _physics_process(delta: float) -> void:
	if not em_uso:
		_pneu_esq_ant = null
		_pneu_dir_ant = null
		_vel_lateral = move_toward(_vel_lateral, 0.0, ATRITO_LATERAL * delta)
		return

	# ── Entrada ──────────────────────────────────────────────────────────────
	var av: float = 0.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		av = 1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		av = -1.0

	var dir: float = 0.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir = 1.0
	elif Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir = -1.0

	# ── Velocidade ───────────────────────────────────────────────────────────
	if av > 0.0:
		_vel = move_toward(_vel, velocidade_maxima, aceleracao * delta)
	elif av < 0.0:
		if _vel > 30.0:
			_vel = move_toward(_vel, 0.0, frenagem * delta)
		else:
			_vel = move_toward(_vel, -velocidade_maxima * velocidade_re, aceleracao * delta)
	else:
		_vel = move_toward(_vel, 0.0, atrito * delta)

	# ── Rotação ──────────────────────────────────────────────────────────────
	var fator: float = clamp(abs(_vel) / velocidade_maxima, 0.0, 1.0)
	rotation_degrees += dir * 310.0 * fator * sign(_vel) * delta

	# ── Derrapagem lateral ───────────────────────────────────────────────────
	if abs(dir) > 0.0 and abs(_vel) > 80.0:
		_vel_lateral += dir * fator * abs(_vel) * 0.45 * delta
	_vel_lateral = clamp(_vel_lateral, -MAX_VEL_LATERAL, MAX_VEL_LATERAL)
	_vel_lateral = move_toward(_vel_lateral, 0.0, ATRITO_LATERAL * delta)

	# ── Movimento (frente + deriva) ──────────────────────────────────────────
	move_and_slide(-transform.y * _vel + transform.x * _vel_lateral, Vector2.ZERO)

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
	if abs(_vel) > 80.0:
		for i in get_slide_count():
			var col = get_slide_collision(i)
			if col == null or col.collider == null:
				continue
			if not col.collider.is_in_group("npc_carros"):
				continue
			if _col_cooldown.has(col.collider):
				continue
			var impact = abs(_vel)
			col.collider.receber_impacto(-col.normal * impact * 0.70)
			var perda = clamp(impact / velocidade_maxima * 0.55, 0.15, 0.55)
			_vel          *= (1.0 - perda)
			_vel_lateral  += col.normal.y * impact * 0.15
			_shake_ampl    = clamp(impact * 0.014, 5.0, 24.0)
			_flash_timer   = FLASH_DURACAO
			_col_cooldown[col.collider] = 0.40
			break

	# ── Atropelamento ────────────────────────────────────────────────────────
	var kmh = abs(_vel) * 0.131
	if kmh > VEL_ATROPELO_KMH:
		for ped in get_tree().get_nodes_in_group("pedestres"):
			if is_instance_valid(ped) and not ped._morto:
				if position.distance_to(ped.position) < RAIO_ATROPELO:
					ped.atropelar()
					get_tree().call_group("hud", "registrar_atropelamento")

	# ── Marcas de pneu ───────────────────────────────────────────────────────
	var pneu_esq = to_global(PNEU_ESQ_LOCAL)
	var pneu_dir = to_global(PNEU_DIR_LOCAL)

	if _pneu_esq_ant != null and abs(_vel_lateral) > LIMIAR_DERRAPA:
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
	var zoom_alvo: float = lerp(1.4, 2.2, fator)
	_camera.zoom = lerp(_camera.zoom, Vector2(zoom_alvo, zoom_alvo), 4.0 * delta)

	emit_signal("velocidade_mudou", abs(_vel) * 0.131)

func receber_impacto_externo(impulso: Vector2) -> void:
	if not em_uso:
		return
	var fwd       = -transform.y
	_vel         += impulso.dot(fwd) * 0.45
	_vel_lateral += impulso.dot(transform.x) * 0.25
	_shake_ampl   = clamp(impulso.length() * 0.010, 2.0, 12.0)
	_flash_timer  = FLASH_DURACAO * 0.5

# ── Marcas de pneu ───────────────────────────────────────────────────────────

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
	# Remove marcas antigas
	while _marcas.size() > MAX_MARCAS:
		var antiga = _marcas.pop_front()
		if is_instance_valid(antiga):
			antiga.queue_free()
