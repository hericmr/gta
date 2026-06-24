# car.gd — Física arcade do carro top-down (KinematicBody2D — Godot 3)
extends KinematicBody2D

export var velocidade_maxima: float  = 1374.0
export var aceleracao: float         = 400.0
export var atrito: float             = 300.0
export var frenagem: float           = 900.0
export var velocidade_re: float      = 0.4

# Derrapagem
const ATRITO_LATERAL   = 380.0   # quão rápido a deriva some
const MAX_VEL_LATERAL  = 280.0   # velocidade lateral máxima
const LIMIAR_DERRAPA   = 20.0    # vel lateral mínima para desenhar marcas
const MAX_MARCAS       = 100     # segmentos de marca mantidos na cena
# Posições locais dos pneus traseiros (ajuste se o carro mudar de visual)
const PNEU_ESQ_LOCAL   = Vector2(-7.5, 150)
const PNEU_DIR_LOCAL   = Vector2(80,  150)

var em_uso: bool        = false setget _set_em_uso
var _vel: float         = 0.0
var _vel_lateral: float = 0.0
var _loader             = null
var _posicao_salva: float = 0.0
var _marcas: Array      = []
var _pneu_esq_ant       = null   # Vector2 | null
var _pneu_dir_ant       = null

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

func _ready() -> void:
	_radio.connect("finished", self, "_on_radio_finished")

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
	rotation_degrees += dir * 195.0 * fator * sign(_vel) * delta

	# ── Derrapagem lateral ───────────────────────────────────────────────────
	if abs(dir) > 0.0 and abs(_vel) > 80.0:
		_vel_lateral += dir * fator * abs(_vel) * 0.45 * delta
	_vel_lateral = clamp(_vel_lateral, -MAX_VEL_LATERAL, MAX_VEL_LATERAL)
	_vel_lateral = move_toward(_vel_lateral, 0.0, ATRITO_LATERAL * delta)

	# ── Movimento (frente + deriva) ──────────────────────────────────────────
	move_and_slide(-transform.y * _vel + transform.x * _vel_lateral, Vector2.ZERO)

	# ── Marcas de pneu ───────────────────────────────────────────────────────
	var pneu_esq = to_global(PNEU_ESQ_LOCAL)
	var pneu_dir = to_global(PNEU_DIR_LOCAL)

	if _pneu_esq_ant != null and abs(_vel_lateral) > LIMIAR_DERRAPA:
		_adicionar_marca(_pneu_esq_ant, pneu_esq)
		_adicionar_marca(_pneu_dir_ant, pneu_dir)

	_pneu_esq_ant = pneu_esq
	_pneu_dir_ant = pneu_dir

	# ── Zoom dinâmico ────────────────────────────────────────────────────────
	var zoom_alvo: float = lerp(1.4, 2.2, fator)
	_camera.zoom = lerp(_camera.zoom, Vector2(zoom_alvo, zoom_alvo), 4.0 * delta)

	emit_signal("velocidade_mudou", abs(_vel) * 0.131)

# ── Marcas de pneu ───────────────────────────────────────────────────────────

func _adicionar_marca(p1: Vector2, p2: Vector2) -> void:
	if p1.distance_squared_to(p2) < 4.0:
		return
	var linha = Line2D.new()
	linha.add_point(p1)
	linha.add_point(p2)
	linha.width         = 4.0
	linha.default_color = Color(0.07, 0.07, 0.07, 0.80)
	linha.z_index       = -5
	get_parent().add_child(linha)
	_marcas.append(linha)
	# Remove marcas antigas
	while _marcas.size() > MAX_MARCAS:
		var antiga = _marcas.pop_front()
		if is_instance_valid(antiga):
			antiga.queue_free()
