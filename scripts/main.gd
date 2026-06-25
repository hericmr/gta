# main.gd — Cena raiz: spawn, câmeras e transição a pé ↔ carro (Godot 3)
extends Node2D

const SPAWN       = Vector2(90124.8, 163182.8)  # lat=-23.984364 lon=-46.308101
const DIST_ENTRAR = 120.0  # pixels para detectar carro próximo

var _stream    = null
var _no_carro  = false
var _debug_t   = 0.0

func _ready() -> void:
	var carro  = $Car
	var player = $Player
	var hud    = $HUD
	var mundo  = $World

	carro.connect("velocidade_mudou", hud, "atualizar_velocidade")

	if mundo.has_meta("satelite_stream"):
		_stream = mundo.get_meta("satelite_stream")

	# Posiciona carro e player próximos
	carro.position  = SPAWN
	player.position = SPAWN + Vector2(80, 0)

	# Começa a pé: player ativo, carro parado
	_modo_a_pe()
	hud.definir_ref(player)
	$NpcTraffic.definir_ref(player)

func _process(delta: float) -> void:
	# Entrar / sair do carro com Enter
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("roubar"):
		if _no_carro:
			_sair_do_carro()
		else:
			_tentar_entrar_carro()

	# Toggle mapa com M
	if Input.is_action_just_pressed("mapa_toggle"):
		$Mapa.toggle()

	# Pega o stream assim que disponível (HTML5: carregamento async)
	if _stream == null and $World.has_meta("satelite_stream"):
		_stream = $World.get_meta("satelite_stream")
		_stream._carro = $Car if _no_carro else $Player

	var ref = $Car if _no_carro else $Player

	# Parallax 2.5D: desloca telhados conforme a câmera se move
	$World.atualizar_parallax(ref.position)

	# Atualiza mapa se visível
	if $Mapa.visible:
		$Mapa.atualizar(ref.position, _stream)

	# Debug de coordenadas (a cada 1 s)
	if _stream == null:
		return
	_debug_t += delta
	if _debug_t < 1.0:
		return
	_debug_t = 0.0
	var pos = ref.position / 15.0
	var lat = _stream._pos_para_lat(pos.y)
	var lon = _stream._pos_para_lon(pos.x)
	print("[POS] lat=%.6f  lon=%.6f" % [lat, lon])

# ── Modos ────────────────────────────────────────────────────────────────────

func _atualizar_touch_ui(no_carro: bool) -> void:
	if not OS.has_touchscreen_ui_hint():
		return
	var ui = $TouchUI/Control
	ui.get_node("BtnRoubar").visible   = not no_carro
	ui.get_node("BtnAtirar").visible   = not no_carro
	ui.get_node("BtnAcelerar").visible = no_carro
	ui.get_node("BtnFrear").visible    = no_carro
	ui.get_node("BtnSair").visible     = no_carro

func _modo_a_pe() -> void:
	var carro  = $Car
	var player = $Player
	_no_carro       = false
	carro.em_uso    = false
	player.ativo    = true
	player.visible  = true
	player.get_node("Camera2D").current = true
	carro.get_node("Camera2D").current  = false
	if _stream:
		_stream._carro = player
	_atualizar_touch_ui(false)

func _tentar_entrar_carro() -> void:
	var player     = $Player
	var dist_carro = $Car.position.distance_to(player.position)

	# Verifica se há NPC mais próximo que o $Car
	var npc = $NpcTraffic.carro_mais_proximo(player.position, DIST_ENTRAR)
	if npc != null and npc.position.distance_to(player.position) < dist_carro:
		# Rouba o NPC: reposiciona $Car no lugar do NPC
		$Car.parar()
		$Car.position = npc.position
		$Car.rotation = npc.rotation
		$Car.get_node("Visual").color = npc.get_child(0).color
		$NpcTraffic.remover_carro(npc)
	elif dist_carro > DIST_ENTRAR:
		return  # nenhum carro próximo

	_no_carro       = true
	$Player.ativo   = false
	$Player.visible = false
	$Car.em_uso     = true
	$Car.get_node("Camera2D").current   = true
	$Player.get_node("Camera2D").current = false
	if _stream:
		_stream._carro = $Car
	$HUD.definir_ref($Car)
	$NpcTraffic.definir_ref($Car)
	_atualizar_touch_ui(true)

func _sair_do_carro() -> void:
	var carro  = $Car
	var player = $Player
	player.position = carro.position + Vector2(80, 0)
	_modo_a_pe()
	$HUD.definir_ref(player)
	$NpcTraffic.definir_ref(player)
