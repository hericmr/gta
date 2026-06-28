# main.gd — Cena raiz: spawn, câmeras e transição a pé ↔ carro (Godot 3)
extends Node2D

const SPAWN       = Vector2(90124.8, 163182.8)  # lat=-23.984364 lon=-46.308101
const DIST_ENTRAR = 120.0  # pixels para detectar carro próximo

var _stream    = null
var _no_carro  = false
var _no_onibus = false
var _onibus_atual = null
var _debug_t   = 0.0
var _rua_t     = 0.0

onready var _car      = $Car
onready var _player   = $Player
onready var _hud      = $HUD
onready var _world    = $World
onready var _mapa     = $Mapa
onready var _traffic  = $NpcTraffic
onready var _onibus   = $NpcOnibusTraffic
onready var _touch_ui = $TouchUI/Control

func _ready() -> void:
	OS.window_fullscreen = true
	randomize()

	# Conecta os sinais de HUD e do Spawn pelo Mapa
	_car.connect("velocidade_mudou", _hud, "atualizar_velocidade")
	_mapa.connect("local_spawn_selecionado", self, "_on_spawn_mapa_selecionado")

	if _world.has_meta("satelite_stream"):
		_stream = _world.get_meta("satelite_stream")

	# Habilita controles a pé por padrão e vincula referências
	_modo_a_pe()
	_hud.definir_ref(_player)
	_traffic.definir_ref(_player)
	_onibus.definir_ref(_player)
	_world.atualizar_parallax(_player.position)

	# Inicia o jogo desativado na tela de seleção de spawn por clique
	_player.ativo = false
	_player.visible = false
	yield(get_tree().create_timer(0.3), "timeout")
	_abrir_mapa_inicial()

func _abrir_mapa_inicial() -> void:
	_mapa.abrir_para_spawn()

func _process(delta: float) -> void:
	if _no_onibus:
		if is_instance_valid(_onibus_atual):
			_player.position = _onibus_atual.position
			
			# Sincroniza o zoom da câmera com a velocidade do ônibus, igual ao do carro
			var speed_len = _onibus_atual._velocity.length()
			var spd_frac = clamp(speed_len / 774.0, 0.0, 1.0)
			var zoom_alvo = lerp(1.15, 1.85, spd_frac)
			var cam = _player.get_node("Camera2D")
			cam.zoom = cam.zoom.linear_interpolate(Vector2(zoom_alvo, zoom_alvo), 4.0 * delta)
		else:
			_sair_do_onibus_forcado()

	if Input.is_action_just_pressed("entrar_carro") or Input.is_action_just_pressed("roubar"):
		if _no_carro:
			_sair_do_carro()
		elif _no_onibus:
			_tentar_sair_do_onibus()
		else:
			_tentar_entrar_carro()

	if Input.is_action_just_pressed("mapa_toggle") and not _mapa.selecionando_spawn:
		_mapa.toggle()

	# DEBUG: F2 teletransporta o player para o ônibus mais próximo
	if OS.is_debug_build() and Input.is_key_pressed(KEY_F2):
		var onibus_lista = get_tree().get_nodes_in_group("npc_onibus")
		if not onibus_lista.empty():
			var alvo = onibus_lista[0]
			_player.position = alvo.position + Vector2(150, 0)
			print("[DEBUG] Teletransportado para ônibus em %s" % alvo.position)

	if _stream == null and _world.has_meta("satelite_stream"):
		_stream = _world.get_meta("satelite_stream")
		_stream._carro = _car if _no_carro else _player

	var ref = _car if _no_carro else _player

	_world.atualizar_parallax(ref.position)

	if _mapa.visible:
		_mapa.atualizar(ref.position, _stream)

	_rua_t += delta
	if _rua_t >= 1.5:
		_rua_t = 0.0
		_hud.atualizar_rua(_world.rua_proxima(ref.position))

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
	_player.get_node("Camera2D").reset_smoothing()
	if _stream:
		_stream._carro = _player
	_atualizar_touch_ui(false)

func _tentar_entrar_carro() -> void:
	var dist_carro = _car.position.distance_to(_player.position)

	# 1. Tenta entrar no ônibus parado no ponto primeiro
	var onibus = _obter_onibus_proximo(_player.global_position, DIST_ENTRAR)
	if onibus != null and onibus.get("_estado") == 2:
		_entrar_no_onibus(onibus)
		return

	# 2. Caso contrário, entra em carro NPC ou do Player
	var npc = _traffic.carro_mais_proximo(_player.position, DIST_ENTRAR)
	if npc != null and npc.position.distance_to(_player.position) < dist_carro:
		_car.parar()
		_car.position = npc.position
		_car.rotation = npc.rotation
		
		# Rouba o carro aplicando o modelo de motor e cor corretos ao carro do player
		var npc_modelo = npc.modelo_idx
		var npc_cor = npc.get_node("Visual").color
		_car.aplicar_modelo(npc_modelo, npc_cor)
		
		_traffic.remover_carro(npc)
	elif dist_carro > DIST_ENTRAR:
		return

	_no_carro          = true
	_player.ativo      = false
	_player.visible    = false
	_car.em_uso        = true
	_car.get_node("Camera2D").current    = true
	_player.get_node("Camera2D").current = false
	_car.get_node("Camera2D").reset_smoothing()
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


# ── Lógica de Passageiro do Ônibus ───────────────────────────────────────────

func _obter_onibus_proximo(pos: Vector2, raio: float):
	var melhor = null
	var melhor_d = raio
	for onibus in get_tree().get_nodes_in_group("npc_onibus"):
		if is_instance_valid(onibus):
			var d = onibus.global_position.distance_to(pos)
			if d < melhor_d:
				melhor_d = d
				melhor = onibus
	return melhor


func _entrar_no_onibus(onibus) -> void:
	_no_onibus = true
	_onibus_atual = onibus
	_player.ativo = false
	_player.visible = false
	_player.collision_layer = 0
	_player.collision_mask = 0
	
	_player.get_node("Camera2D").reset_smoothing()
	
	if _stream:
		_stream._carro = _onibus_atual
	_hud.definir_ref(_onibus_atual)
	_traffic.definir_ref(_onibus_atual)
	_atualizar_touch_ui(false)
	_hud.atualizar_rua("EMBARCADO COMO PASSAGEIRO")


func _tentar_sair_do_onibus() -> void:
	if not is_instance_valid(_onibus_atual):
		_sair_do_onibus_forcado()
		return
		
	# Só pode descer se o ônibus estiver parado no ponto (Estado.PARADO_PONTO = 2)
	if _onibus_atual.get("_estado") == 2:
		_sair_do_onibus()
	else:
		_hud.atualizar_rua("DESÇA APENAS NOS PONTOS DE ÔNIBUS!")


func _sair_do_onibus() -> void:
	_no_onibus = false
	
	# Desce na calçada do lado direito do ônibus
	var lado = _onibus_atual.transform.x
	_player.position = _onibus_atual.position + lado * 100.0
	
	_player.visible = true
	_player.ativo = true
	_player.collision_layer = 8
	_player.collision_mask = 1
	_player.get_node("Camera2D").zoom = Vector2(0.7, 0.7) # Reseta para o zoom padrão a pé
	_player.get_node("Camera2D").current = true
	_player.get_node("Camera2D").reset_smoothing()
	
	if _stream:
		_stream._carro = _player
	_hud.definir_ref(_player)
	_traffic.definir_ref(_player)
	_onibus_atual = null
	_hud.atualizar_rua("VOCÊ DESEMBARCOU")


func _sair_do_onibus_forcado() -> void:
	_no_onibus = false
	_player.visible = true
	_player.ativo = true
	_player.collision_layer = 8
	_player.collision_mask = 1
	_player.get_node("Camera2D").zoom = Vector2(0.7, 0.7) # Reseta para o zoom padrão a pé
	_player.get_node("Camera2D").current = true
	_player.get_node("Camera2D").reset_smoothing()
	
	if _stream:
		_stream._carro = _player
	_hud.definir_ref(_player)
	_traffic.definir_ref(_player)
	_onibus_atual = null


# ── Seleção de Local de Spawn Inicial ────────────────────────────────────────

func _on_spawn_mapa_selecionado(spawn_pos: Vector2) -> void:
	# Teletransporta player e carro
	_player.position = spawn_pos
	_car.position = spawn_pos + Vector2(80, 0)
	
	# Libera controles e reinicializa sistemas
	_player.ativo = true
	_player.visible = true
	
	_player.get_node("Camera2D").current = true
	_player.get_node("Camera2D").reset_smoothing()
	_world.atualizar_parallax(spawn_pos)
	if _stream:
		_stream._carro = _player
	_hud.definir_ref(_player)
	_traffic.definir_ref(_player)
	_onibus.definir_ref(_player)
	
	_hud.atualizar_rua("BEM-VINDO A SANTOS")
	print("[SPAWN] Player iniciado no clique do mapa: %s" % spawn_pos)
