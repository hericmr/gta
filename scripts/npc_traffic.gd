# npc_traffic.gd — Carros NPC + Pedestres NPC nas ruas (Godot 3)
extends Node2D

const URL_JSON = "https://hericmr.github.io/gta/maps/santos.json"
const URL_LINHAS = "https://hericmr.github.io/gta/newdata/linhas_onibus.json"

# preload garante inclusão no PCK ao exportar (load(variável) não é detectado)
const NpcCarScript      = preload("res://scripts/npc_car.gd")
const NpcPedestreScript = preload("res://scripts/npc_pedestre.gd")

const ESCALA             = 15.0
const MARGEM             = 600.0
const LARGURA_MIN_CARRO  = 5     # ruas com largura < 5 → só pedestres

# Carros
const VEL_MIN    = 400.0
const VEL_MAX    = 720.0

# Pedestres
const VEL_PED_MIN  = 150.0
const VEL_PED_MAX  = 210.0

# Contagem: reduzida automaticamente no celular
var N_CARROS    = 35
var N_PEDESTRES = 200

const RAIO_SPAWN   = 5000.0
const RAIO_DESPAWN = 7500.0
const MIN_PTS      = 4

# Grafo de conectividade
const RAIO_CONEXAO  = 350.0  # px — distância máxima entre endpoints para pré-conectar ruas
const GRADE_CONEXAO = 300.0  # px — célula da grade auxiliar usada na construção do grafo
const SNAP_VIZIN    = 4      # células ±N toleradas na busca de saídas em tempo real

var _ruas_carro:  Array      = []
var _ruas_ped:    Array      = []
var _grafo_carro: Dictionary = {}   # snap_key → [{wps, oneway}] saídas desse ponto
var _grafo_ped:   Dictionary = {}

var _carros:   Array      = []
var _car_wps:  Dictionary = {}
var _car_ow:   Dictionary = {}

var _pedestres: Array      = []
var _ped_wps:   Dictionary = {}
var _ped_ow:    Dictionary = {}

var _ref             = null
var _process_timer:  float = 0.0
var PROCESS_INTERVAL = 0.5

var _paradas_onibus: Array = []   # posições (px) das paradas de ônibus de Santos


func _ready() -> void:
	if OS.has_touchscreen_ui_hint():
		N_CARROS         = 10
		N_PEDESTRES      = 40
		PROCESS_INTERVAL = 1.0

	if OS.get_name() == "HTML5":
		var req_paradas = HTTPRequest.new()
		add_child(req_paradas)
		req_paradas.connect("request_completed", self, "_on_paradas_json_carregado")
		req_paradas.request(URL_LINHAS)

		var req = HTTPRequest.new()
		add_child(req)
		req.connect("request_completed", self, "_on_json_carregado")
		req.request(URL_JSON)
	else:
		_carregar_ruas()


func _on_paradas_json_carregado(_result, code, _headers, body) -> void:
	if code != 200:
		push_warning("[Traffic] Falha HTTP ao carregar paradas (code=%d)" % code)
		return
	var dados = parse_json(body.get_string_from_utf8())
	if dados:
		for linha in dados.get("linhas", []):
			for p in linha.get("paradas_px", []):
				_paradas_onibus.append(Vector2(p["x"] * ESCALA, p["y"] * ESCALA))
		print("[Traffic] %d paradas de ônibus carregadas via HTTP" % _paradas_onibus.size())


func definir_ref(no) -> void:
	_ref = no
	if _carros.empty() and not _ruas_carro.empty():
		_spawnar_pool(_carros, _ruas_carro, N_CARROS, _car_wps, _car_ow,
				NpcCarScript, VEL_MIN, VEL_MAX, "_on_fim_carro")
	if _pedestres.empty() and not _ruas_ped.empty():
		_spawnar_pool(_pedestres, _ruas_ped, N_PEDESTRES, _ped_wps, _ped_ow,
				NpcPedestreScript, VEL_PED_MIN, VEL_PED_MAX, "_on_fim_ped")


func _on_json_carregado(_result, code, _headers, body) -> void:
	if code != 200:
		push_warning("[Traffic] Falha HTTP ao carregar santos.json (code=%d)" % code)
		return
	var d = parse_json(body.get_string_from_utf8())
	if d:
		_processar_ruas(d)


func _carregar_ruas() -> void:
	_carregar_paradas_onibus()   # precisa estar pronto antes de spawnar pedestres
	var arq = File.new()
	if not arq.file_exists("res://maps/santos.json"):
		push_warning("[Traffic] santos.json não encontrado")
		return
	arq.open("res://maps/santos.json", File.READ)
	var d = parse_json(arq.get_as_text())
	arq.close()
	if d:
		_processar_ruas(d)


func _carregar_paradas_onibus() -> void:
	var arq = File.new()
	var caminho = "res://newdata/linhas_onibus.json"
	if not arq.file_exists(caminho):
		return
	arq.open(caminho, File.READ)
	var dados = parse_json(arq.get_as_text())
	arq.close()
	if not dados:
		return
	for linha in dados.get("linhas", []):
		for p in linha.get("paradas_px", []):
			_paradas_onibus.append(Vector2(p["x"] * ESCALA, p["y"] * ESCALA))
	print("[Traffic] %d paradas de ônibus indexadas" % _paradas_onibus.size())


func _offset_wps(wps: PoolVector2Array, offset: float) -> PoolVector2Array:
	var result = PoolVector2Array()
	var n = wps.size()
	for i in range(n):
		var perp: Vector2
		if n == 1:
			perp = Vector2.RIGHT
		elif i == 0:
			perp = (wps[1] - wps[0]).normalized().rotated(PI * 0.5)
		elif i == n - 1:
			perp = (wps[i] - wps[i - 1]).normalized().rotated(PI * 0.5)
		else:
			var d1 = (wps[i] - wps[i - 1]).normalized()
			var d2 = (wps[i + 1] - wps[i]).normalized()
			perp = ((d1 + d2) * 0.5)
			if perp.length() > 0.01:
				perp = perp.normalized().rotated(PI * 0.5)
			else:
				perp = d1.rotated(PI * 0.5)
		result.append(wps[i] + perp * offset)
	return result


func _processar_ruas(d: Dictionary) -> void:
	for rua in d.get("ruas", []):
		var pts = rua["pontos"]
		if len(pts) < MIN_PTS:
			continue
		var arr = PoolVector2Array()
		for p in pts:
			arr.append(Vector2(p[0] * ESCALA, p[1] * ESCALA))
		var largura = rua.get("largura", 4)
		var oneway  = rua.get("oneway", false)
		var entrada = {"wps": arr, "oneway": oneway}
		if largura >= LARGURA_MIN_CARRO:
			if largura >= 7:
				var lane_offset = largura * 0.25 * ESCALA
				var lane_esq = _offset_wps(arr, lane_offset)
				var lane_dir = _offset_wps(arr, -lane_offset)
				if lane_esq.size() >= MIN_PTS:
					_ruas_carro.append({"wps": lane_esq, "oneway": oneway})
				if lane_dir.size() >= MIN_PTS:
					_ruas_carro.append({"wps": lane_dir, "oneway": oneway})
			else:
				_ruas_carro.append(entrada)

			# Gera calçadas paralelas em ambos os lados da rua
			var offset_extra = 8.0 if largura >= 7 else 6.0
			var offset_px = (largura * 0.5 + offset_extra) * ESCALA
			var cal_esq = _offset_wps(arr, offset_px)
			var cal_dir = _offset_wps(arr, -offset_px)
			if cal_esq.size() >= MIN_PTS:
				_ruas_ped.append({"wps": cal_esq, "oneway": false})
			if cal_dir.size() >= MIN_PTS:
				_ruas_ped.append({"wps": cal_dir, "oneway": false})
		else:
			_ruas_ped.append(entrada)
	_grafo_carro = _construir_grafo(_ruas_carro)
	_grafo_ped   = _construir_grafo(_ruas_ped)
	print("[Traffic] carros:%d ped:%d  nós grafo carro:%d ped:%d" % [
		_ruas_carro.size(), _ruas_ped.size(),
		_grafo_carro.size(), _grafo_ped.size()])
	# HTML5: definir_ref já foi chamado antes do fetch terminar → spawna agora
	if _ref != null:
		definir_ref(_ref)


func _rect_visivel() -> Rect2:
	var vp  = get_viewport()
	var inv = vp.get_canvas_transform().affine_inverse()
	var sz  = vp.size
	var tl  = inv.xform(Vector2.ZERO)
	var br  = inv.xform(sz)
	return Rect2(tl - Vector2(MARGEM, MARGEM),
				 (br - tl) + Vector2(MARGEM * 2.0, MARGEM * 2.0))


func _process(delta: float) -> void:
	if _ref == null:
		return
	_process_timer += delta
	if _process_timer < PROCESS_INTERVAL:
		return
	_process_timer = 0.0
	var rect = _rect_visivel()
	_verificar_pool(_carros, _ruas_carro, _car_wps, _car_ow,
			"res://scripts/npc_car.gd", VEL_MIN, VEL_MAX, "_on_fim_carro", rect)
	_verificar_pool(_pedestres, _ruas_ped, _ped_wps, _ped_ow,
			"res://scripts/npc_pedestre.gd", VEL_PED_MIN, VEL_PED_MAX, "_on_fim_ped", rect)


# ── Genérico ──────────────────────────────────────────────────────────────────

func _spawnar_pool(pool, ruas, n, wps_dict, ow_dict, script_path, v_min, v_max, cb) -> void:
	for _i in range(n):
		var c = _criar_npc(ruas, wps_dict, ow_dict, script_path, v_min, v_max, cb)
		if c:
			pool.append(c)


func _verificar_pool(pool, ruas, wps_dict, ow_dict, script_path, v_min, v_max, cb, rect) -> void:
	for npc in pool:
		if not is_instance_valid(npc):
			continue
		if npc.get("no_onibus"):
			continue
		var fora = not rect.has_point(npc.position)
		var morto = npc.get("_morto")
		if fora and (morto or npc.position.distance_to(_ref.position) > RAIO_DESPAWN):
			_resetar_npc(npc, ruas, wps_dict, ow_dict, v_min, v_max, rect)


func _criar_npc(ruas, wps_dict, ow_dict, script_res, v_min, v_max, cb):
	var rect = _rect_visivel()
	var info = _wps_fora_de_camera(ruas, rect)
	if info.empty():
		return null
	var c = script_res.new()
	add_child(c)
	var vel = lerp(v_min, v_max, randf())
	var wps = info.wps
	# 25% dos pedestres caminham até a parada de ônibus mais próxima
	if script_res == NpcPedestreScript and not _paradas_onibus.empty() and randf() < 0.25:
		var parada = _parada_proxima(wps[info.start], 6000.0)
		if parada != Vector2.ZERO:
			wps = PoolVector2Array(wps)
			var desvio = Vector2(rand_range(-55.0, 55.0), rand_range(-55.0, 55.0))
			wps.append(parada + desvio)
	c.inicializar(wps, vel, info.start)
	wps_dict[c] = wps
	ow_dict[c]  = info.oneway
	c.connect("chegou_ao_fim", self, cb, [c])
	return c


func _parada_proxima(pos: Vector2, raio: float) -> Vector2:
	var melhor   = Vector2.ZERO
	var melhor_d = raio
	for p in _paradas_onibus:
		var d = p.distance_to(pos)
		if d < melhor_d:
			melhor_d = d
			melhor   = p
	return melhor


func _perto_de_parada(pos: Vector2, raio: float) -> bool:
	for p in _paradas_onibus:
		if p.distance_to(pos) < raio:
			return true
	return false


func _resetar_npc(npc, ruas, wps_dict, ow_dict, v_min, v_max, rect) -> void:
	var info = _wps_fora_de_camera(ruas, rect)
	if info.empty():
		return
	var vel = lerp(v_min, v_max, randf())
	var wps = info.wps
	if npc.is_in_group("pedestres") and not _paradas_onibus.empty() and randf() < 0.25:
		var parada = _parada_proxima(wps[info.start], 6000.0)
		if parada != Vector2.ZERO:
			wps = PoolVector2Array(wps)
			var desvio = Vector2(rand_range(-55.0, 55.0), rand_range(-55.0, 55.0))
			wps.append(parada + desvio)
	npc.inicializar(wps, vel, info.start)
	wps_dict[npc] = wps
	ow_dict[npc]  = info.oneway


func _on_fim_carro(carro) -> void:
	_on_fim_npc(carro, _ruas_carro, _grafo_carro, _car_wps, _car_ow, VEL_MIN, VEL_MAX)

func _on_fim_ped(ped) -> void:
	if not is_instance_valid(ped):
		return
	if not _paradas_onibus.empty() and _perto_de_parada(ped.position, 230.0):
		if ped.get("recem_desembarcado"):
			ped.recem_desembarcado = false
		else:
			ped._esperando_onibus = true
			return
	_on_fim_npc(ped, _ruas_ped, _grafo_ped, _ped_wps, _ped_ow, VEL_PED_MIN, VEL_PED_MAX)

func _on_fim_npc(npc, ruas, grafo, wps_dict, ow_dict, v_min, v_max) -> void:
	if not is_instance_valid(npc):
		return

	var wps_atual: PoolVector2Array = wps_dict.get(npc, PoolVector2Array())
	var vel = lerp(v_min, v_max, randf())

	# ── Segue a próxima rua conectada pelo grafo ──────────────────────────────
	if wps_atual.size() >= 2:
		var fim    = wps_atual[wps_atual.size() - 1]
		var saidas = _buscar_saidas(grafo, fim)
		if not saidas.empty():
			var inicio_atual = wps_atual[0]
			# Filtra rotas que levam de volta para onde viemos
			var candidatas = []
			for s in saidas:
				if s["wps"][s["wps"].size() - 1].distance_to(inicio_atual) > 50.0:
					candidatas.append(s)
			if candidatas.empty():
				candidatas = saidas
			var proxima = candidatas[randi() % candidatas.size()]
			npc.reinicializar(proxima["wps"], vel)
			wps_dict[npc] = proxima["wps"]
			ow_dict[npc]  = proxima["oneway"]
			return

	# ── Grafo falhou: inverte a rota atual e continua sem teletransportar ────
	var rect = _rect_visivel()
	if wps_atual.size() > 1 and not ow_dict.get(npc, false):
		var inv = _inverter(wps_atual)
		npc.inicializar(inv, vel, 0)
		wps_dict[npc] = inv
		return
	
	# Fail-safe: se não pode inverter (rua de mão única ou fim de rota),
	# reseta/teletransporta o NPC para manter o tráfego fluindo
	_resetar_npc(npc, ruas, wps_dict, ow_dict, v_min, v_max, rect)


func _wps_fora_de_camera(ruas, rect: Rect2) -> Dictionary:
	for _t in range(80):
		var rua = _rua_aleatoria_perto(ruas)
		if rua.empty():
			continue
		var wps    = rua["wps"]
		var oneway = rua["oneway"]
		if not oneway and randi() % 2 == 0:
			wps = _inverter(wps)
		for i in range(wps.size()):
			if not rect.has_point(wps[i]):
				return {"wps": wps, "start": i, "oneway": oneway}
	return {}


func _rua_aleatoria_perto(ruas) -> Dictionary:
	if ruas.empty():
		return {}
	if _ref == null:
		return ruas[randi() % ruas.size()]
	for _t in range(40):
		var r = ruas[randi() % ruas.size()]
		var meio = r["wps"][r["wps"].size() / 2]
		if meio.distance_to(_ref.position) < RAIO_SPAWN:
			return r
	return ruas[randi() % ruas.size()]


func _inverter(wps: PoolVector2Array) -> PoolVector2Array:
	var inv = PoolVector2Array()
	for i in range(wps.size() - 1, -1, -1):
		inv.append(wps[i])
	return inv


# ── Grafo de conectividade ────────────────────────────────────────────────────

func _snap_key(pos: Vector2) -> String:
	return str(int(round(pos.x / ESCALA))) + "_" + str(int(round(pos.y / ESCALA)))


# Busca saídas no grafo — tolerância ±SNAP_VIZIN células para cobrir imprecisão de float
func _buscar_saidas(grafo: Dictionary, pos: Vector2) -> Array:
	var cx = int(round(pos.x / ESCALA))
	var cy = int(round(pos.y / ESCALA))
	# Coleta TODAS as saídas dentro da vizinhança (não para na primeira)
	var resultado: Array = []
	for dx in range(-SNAP_VIZIN, SNAP_VIZIN + 1):
		for dy in range(-SNAP_VIZIN, SNAP_VIZIN + 1):
			var k = str(cx + dx) + "_" + str(cy + dy)
			if grafo.has(k):
				resultado.append_array(grafo[k])
	return resultado


# Constrói o grafo pré-computando conexões com raio RAIO_CONEXAO:
# para cada ponto de saída de uma rua, encontra TODAS as ruas que partem de dentro desse raio.
# Isso torna o grafo robusto a imprecisões GPS e a ruas que quase se tocam nas interseções.
func _construir_grafo(ruas: Array) -> Dictionary:
	# Fase 1: coleta todos os pontos de entrada (início de cada percurso possível)
	var entradas: Array = []
	for rua in ruas:
		var wps: PoolVector2Array = rua["wps"]
		if wps.size() < 2:
			continue
		entradas.append({"pos": wps[0], "wps": wps, "ow": rua["oneway"]})
		if not rua["oneway"]:
			var inv = _inverter(wps)
			entradas.append({"pos": inv[0], "wps": inv, "ow": false})

	# Fase 2: indexa entradas numa grade espacial grosseira para busca eficiente O(1)
	var grade: Dictionary = {}
	for e in entradas:
		var gk = str(int(e["pos"].x / GRADE_CONEXAO)) + "_" + str(int(e["pos"].y / GRADE_CONEXAO))
		if not grade.has(gk):
			grade[gk] = []
		grade[gk].append(e)

	# Fase 3: para cada ponto de saída, pré-computa as ruas conectadas dentro de RAIO_CONEXAO
	var grafo: Dictionary = {}
	for rua in ruas:
		var wps: PoolVector2Array = rua["wps"]
		if wps.size() < 2:
			continue
		_grafo_preencher_saida(grafo, wps[wps.size() - 1], grade)
		if not rua["oneway"]:
			_grafo_preencher_saida(grafo, wps[0], grade)

	var total = 0
	for k in grafo:
		total += grafo[k].size()
	print("[Traffic] grafo: %d nós, %d conexões" % [grafo.size(), total])
	return grafo


func _grafo_preencher_saida(grafo: Dictionary, pos_saida: Vector2, grade: Dictionary) -> void:
	var chave = _snap_key(pos_saida)
	if not grafo.has(chave):
		grafo[chave] = []
	var gcx = int(pos_saida.x / GRADE_CONEXAO)
	var gcy = int(pos_saida.y / GRADE_CONEXAO)
	# Verifica células vizinhas da grade auxiliar (2×2 cobre o raio)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var gk = str(gcx + dx) + "_" + str(gcy + dy)
			if not grade.has(gk):
				continue
			for e in grade[gk]:
				if e["pos"].distance_to(pos_saida) <= RAIO_CONEXAO:
					grafo[chave].append({"wps": e["wps"], "oneway": e["ow"]})


func _rua_mais_proxima(ruas: Array, pos: Vector2, raio: float) -> Dictionary:
	var melhor   = {}
	var melhor_d = raio
	for rua in ruas:
		var wps: PoolVector2Array = rua["wps"]
		var meio = wps[wps.size() / 2]
		var d = meio.distance_to(pos)
		if d < melhor_d:
			melhor_d = d
			melhor   = rua
	return melhor


# ── API pública ───────────────────────────────────────────────────────────────

func carro_mais_proximo(pos: Vector2, raio: float):
	var melhor      = null
	var melhor_dist = raio
	for c in _carros:
		if not is_instance_valid(c):
			continue
		var d = c.position.distance_to(pos)
		if d < melhor_dist:
			melhor_dist = d
			melhor      = c
	return melhor


func remover_carro(carro) -> void:
	_carros.erase(carro)
	_car_wps.erase(carro)
	_car_ow.erase(carro)
	if is_instance_valid(carro):
		carro.queue_free()
