# main.gd — Cena raiz: spawn, câmeras e transição a pé ↔ carro (Godot 3)
extends Node2D

const SPAWN       = Vector2(90124.8, 163182.8)  # lat=-23.984364 lon=-46.308101
const DIST_ENTRAR = 120.0  # pixels para detectar carro próximo

var _stream    = null
var _no_carro  = false
var _debug_t   = 0.0

onready var _car      = $Car
onready var _player   = $Player
onready var _hud      = $HUD
onready var _world    = $World
onready var _mapa     = $Mapa
onready var _traffic  = $NpcTraffic
onready var _touch_ui = $TouchUI/Control

func _ready() -> void:
	_car.connect("velocidade_mudou", _hud, "atualizar_velocidade")

	if _world.has_meta("satelite_stream"):
		_stream = _world.get_meta("satelite_stream")

	_car.position    = SPAWN
	_player.position = SPAWN + Vector2(80, 0)

	_modo_a_pe()
	_hud.definir_ref(_player)
	_traffic.definir_ref(_player)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("roubar"):
		if _no_carro:
			_sair_do_carro()
		else:
			_tentar_entrar_carro()

	if Input.is_action_just_pressed("mapa_toggle"):
		_mapa.toggle()

	if _stream == null and _world.has_meta("satelite_stream"):
		_stream = _world.get_meta("satelite_stream")
		_stream._carro = _car if _no_carro else _player

	var ref = _car if _no_carro else _player

	_world.atualizar_parallax(ref.position)

	if _mapa.visible:
		_mapa.atualizar(ref.position, _stream)

	if OS.is_debug_build() and _stream != null:
		_debug_t += delta
		if _debug_t >= 1.0:
			_debug_t = 0.0
			var pos = ref.position / 15.0
			var lat = _stream._pos_para_lat(pos.y)
			var lon = _stream._pos_para_lon(pos.x)
			print("[POS] lat=%.6f  lon=%.6f" % [lat, lon])

# ── Modos ────────────────────────────────────────────────────────────────────

func _atualizar_touch_ui(no_carro: bool) -> void:
	if not OS.has_touchscreen_ui_hint():
		return
	_touch_ui.get_node("BtnRoubar").visible       = not no_carro
	_touch_ui.get_node("BtnAtirar").visible       = not no_carro
	_touch_ui.get_node("BtnAcelerar").visible     = no_carro
	_touch_ui.get_node("BtnFrear").visible        = no_carro
	_touch_ui.get_node("BtnSair").visible         = no_carro
	_touch_ui.get_node("BtnVirarEsq").visible     = no_carro
	_touch_ui.get_node("BtnVirarDir").visible     = no_carro
	_touch_ui.get_node("VirtualJoystick").visible = not no_carro

func _modo_a_pe() -> void:
	_no_carro          = false
	_car.em_uso        = false
	_player.ativo      = true
	_player.visible    = true
	_player.get_node("Camera2D").current = true
	_car.get_node("Camera2D").current    = false
	if _stream:
		_stream._carro = _player
	_atualizar_touch_ui(false)

func _tentar_entrar_carro() -> void:
	var dist_carro = _car.position.distance_to(_player.position)

	var npc = _traffic.carro_mais_proximo(_player.position, DIST_ENTRAR)
	if npc != null and npc.position.distance_to(_player.position) < dist_carro:
		_car.parar()
		_car.position = npc.position
		_car.rotation = npc.rotation
		_car.get_node("Visual").color = npc.get_child(0).color
		_traffic.remover_carro(npc)
	elif dist_carro > DIST_ENTRAR:
		return

	_no_carro          = true
	_player.ativo      = false
	_player.visible    = false
	_car.em_uso        = true
	_car.get_node("Camera2D").current    = true
	_player.get_node("Camera2D").current = false
	if _stream:
		_stream._carro = _car
	_hud.definir_ref(_car)
	_traffic.definir_ref(_car)
	_atualizar_touch_ui(true)

func _sair_do_carro() -> void:
	_player.position = _car.position + Vector2(80, 0)
	_modo_a_pe()
	_hud.definir_ref(_player)
	_traffic.definir_ref(_player)
