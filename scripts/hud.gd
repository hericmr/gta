# hud.gd — Velocímetro, pontuação e combo de atropelamentos (Godot 3)
extends CanvasLayer

const M_POR_GAME_UNIT = 0.03638

const COMBO_JANELA  = 2.2   # segundos para manter o combo vivo
const PONTOS_COMBO  = [20, 50, 100, 150, 200, 500, 1000]
const CORES_COMBO   = [
	Color(1.00, 1.00, 1.00),  # branco
	Color(1.00, 0.92, 0.00),  # amarelo
	Color(1.00, 0.50, 0.00),  # laranja
	Color(1.00, 0.15, 0.15),  # vermelho
	Color(1.00, 0.00, 0.80),  # magenta
	Color(0.40, 0.00, 1.00),  # roxo
	Color(0.00, 1.00, 1.00),  # ciano
]

onready var _label:       Label  = $Control/LabelVel
onready var _label_score: Label  = $Control/LabelScore
onready var _label_combo: Label  = $Control/LabelCombo
onready var _label_rua:   Label  = $Control/LabelRua
onready var _tween:       Tween  = $Tween

var _pos_anterior:    Vector2 = Vector2.ZERO
var _ref_node                 = null

var _pontuacao:       int   = 0
var _combo:           int   = 0
var _combo_timer:     float = 0.0
var _combo_pos_base:  float = 0.0
var _rua_atual:       String = ""
var _rua_fade_t:      float  = 0.0
var _minimapa                = null


func _ready() -> void:
	add_to_group("hud")
	_label_combo.rect_scale = Vector2(3.0, 3.0)
	_combo_pos_base = _label_combo.rect_position.y
	_criar_minimapa()


func atualizar_velocidade(kmh: float, marcha: int = 1) -> void:
	var marcha_str = ""
	if marcha == 0:
		marcha_str = "N"
	elif marcha == -1:
		marcha_str = "R"
	else:
		marcha_str = "%d" % marcha
	_label.text = "%d km/h [%s]" % [int(kmh), marcha_str]


func atualizar_rua(nome: String) -> void:
	if nome == "" or nome == _rua_atual:
		return
	_rua_atual          = nome
	_label_rua.text     = nome
	_label_rua.modulate = Color(1, 1, 1, 1)
	_rua_fade_t         = 4.0


func definir_ref(no) -> void:
	_ref_node     = no
	_pos_anterior = no.position


func registrar_atropelamento() -> void:
	_combo       += 1
	_combo_timer  = COMBO_JANELA

	var idx = min(_combo - 1, PONTOS_COMBO.size() - 1)
	var pts = PONTOS_COMBO[idx]
	_pontuacao += pts
	_label_score.text = str(_pontuacao)

	var cor = CORES_COMBO[min(_combo - 1, CORES_COMBO.size() - 1)]
	_label_combo.text     = str(pts) + "!"
	_label_combo.modulate = cor

	_tween.stop_all()
	# Reseta posição Y antes de animar para cima
	_label_combo.rect_position.y = _combo_pos_base
	_tween.interpolate_property(_label_combo, "rect_position:y",
			_combo_pos_base, _combo_pos_base - 18,
			0.35, Tween.TRANS_QUAD, Tween.EASE_OUT)
	_tween.interpolate_property(_label_combo, "modulate:a",
			1.0, 0.0, 1.1, Tween.TRANS_QUAD, Tween.EASE_IN, 0.5)
	_tween.start()


func _process(delta: float) -> void:
	if _rua_fade_t > 0.0:
		_rua_fade_t -= delta
		_label_rua.modulate.a = clamp(_rua_fade_t, 0.0, 1.0)

	# Combo timeout
	if _combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0

	# Velocidade real (debug)
	if _ref_node == null or delta <= 0.0:
		return
	var deslocamento_units = _ref_node.position.distance_to(_pos_anterior) / delta
	_pos_anterior = _ref_node.position
	var kmh_real = deslocamento_units * M_POR_GAME_UNIT * 3.6

	if _minimapa:
		_minimapa.atualizar(_ref_node.position, _ref_node.rotation)


func _criar_minimapa() -> void:
	var MiniMapaScript = load("res://scripts/minimapa.gd")
	_minimapa = Control.new()
	_minimapa.name = "MiniMapa"
	_minimapa.set_script(MiniMapaScript)
	
	# Configura posição e âncoras (Canto Superior Esquerdo: 110x110 px)
	_minimapa.anchor_left = 0.0
	_minimapa.anchor_right = 0.0
	_minimapa.margin_left = 20.0
	_minimapa.margin_top = 20.0
	_minimapa.margin_right = 130.0
	_minimapa.margin_bottom = 130.0
	_minimapa.rect_min_size = Vector2(110, 110)
	_minimapa.rect_size = Vector2(110, 110)
	_minimapa.rect_clip_content = false
	
	$Control.add_child(_minimapa)
