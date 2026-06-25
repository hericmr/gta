# npc_traffic.gd — Carros NPC + Pedestres NPC nas ruas (Godot 3)
extends Node2D

const URL_JSON = "https://hericmr.github.io/gta/maps/santos.json"

# preload garante inclusão no PCK ao exportar (load(variável) não é detectado)
const NpcCarScript      = preload("res://scripts/npc_car.gd")
const NpcPedestreScript = preload("res://scripts/npc_pedestre.gd")

const ESCALA             = 15.0
const MARGEM             = 600.0
const LARGURA_MIN_CARRO  = 5     # ruas com largura < 5 → só pedestres

# Carros
const N_CARROS   = 20
const VEL_MIN    = 250.0
const VEL_MAX    = 530.0

# Pedestres
const N_PEDESTRES  = 120
const VEL_PED_MIN  = 150.0
const VEL_PED_MAX  = 210.0

const RAIO_SPAWN   = 5000.0
const RAIO_DESPAWN = 7500.0
const MIN_PTS      = 4

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

var _ref = null


func _ready() -> void:
	if OS.get_name() == "HTML5":
		var req = HTTPRequest.new()
		add_child(req)
		req.connect("request_completed", self, "_on_json_carregado")
		req.request(URL_JSON)
	else:
		_carregar_ruas()


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
	var arq = File.new()
	if not arq.file_exists("res://maps/santos.json"):
		push_warning("[Traffic] santos.json não encontrado")
		return
	arq.open("res://maps/santos.json", File.READ)
	var d = parse_json(arq.get_as_text())
	arq.close()
	if d:
		_processar_ruas(d)


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
			_ruas_carro.append(entrada)
			# Gera calçadas paralelas em ambos os lados da rua
			var offset_px = (largura * 0.5 + 2.5) * ESCALA
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


func _process(_delta: float) -> void:
	if _ref == null:
		return
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
	c.inicializar(info.wps, vel, info.start)
	wps_dict[c] = info.wps
	ow_dict[c]  = info.oneway
	c.connect("chegou_ao_fim", self, cb, [c])
	return c


func _resetar_npc(npc, ruas, wps_dict, ow_dict, v_min, v_max, rect) -> void:
	var info = _wps_fora_de_camera(ruas, rect)
	if info.empty():
		return
	var vel = lerp(v_min, v_max, randf())
	if npc.has_method("reinicializar"):
		npc.reinicializar(info.wps, vel, info.start)
	else:
		npc.inicializar(info.wps, vel, info.start)
	wps_dict[npc] = info.wps
	ow_dict[npc]  = info.oneway


func _on_fim_carro(carro) -> void:
	_on_fim_npc(carro, _ruas_carro, _grafo_carro, _car_wps, _car_ow, VEL_MIN, VEL_MAX)

func _on_fim_ped(ped) -> void:
	_on_fim_npc(ped, _ruas_ped, _grafo_ped, _ped_wps, _ped_ow, VEL_PED_MIN, VEL_PED_MAX)

func _on_fim_npc(npc, ruas, grafo, wps_dict, ow_dict, v_min, v_max) -> void:
	if not is_instance_valid(npc):
		return

	var wps_atual: PoolVector2Array = wps_dict.get(npc, PoolVector2Array())
	var vel = lerp(v_min, v_max, randf())

	# ── Tenta seguir a próxima rua conectada ─────────────────────────────────
	if wps_atual.size() >= 2:
		var fim   = wps_atual[wps_atual.size() - 1]
		var saidas: Array = _buscar_saidas(grafo, fim)
		if not saidas.empty():
			# Remove a rota de onde viemos (evita inversão trivial como única opção)
			var inicio_atual = wps_atual[0]
			var candidatas = []
			for s in saidas:
				# Filtra: rota que leva de volta ao início da rua atual
				if s["wps"][s["wps"].size() - 1].distance_to(inicio_atual) > 50.0:
					candidatas.append(s)
			if candidatas.empty():
				candidatas = saidas  # fallback: aceita qualquer saída
			var proxima = candidatas[randi() % candidatas.size()]
			npc.inicializar(proxima["wps"], vel, 0)
			wps_dict[npc] = proxima["wps"]
			ow_dict[npc]  = proxima["oneway"]
			return

	# ── Sem conexão no grafo: usa lógica anterior ─────────────────────────────
	var rect = _rect_visivel()
	if rect.has_point(npc.position):
		if not ow_dict.get(npc, false):
			var inv = _inverter(wps_atual)
			if inv.size() > 0:
				npc.inicializar(inv, vel, 0)
				wps_dict[npc] = inv
	else:
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


# Busca saídas no grafo — checa célula exata primeiro, depois vizinhança 3×3
func _buscar_saidas(grafo: Dictionary, pos: Vector2) -> Array:
	var cx = int(round(pos.x / ESCALA))
	var cy = int(round(pos.y / ESCALA))
	# Centro primeiro (correspondência exata)
	var k0 = str(cx) + "_" + str(cy)
	if grafo.has(k0):
		return grafo[k0]
	# Vizinhança para tolerar pequenas diferenças de float
	for dx in [-1, 1, 0]:
		for dy in [-1, 1, 0]:
			if dx == 0 and dy == 0:
				continue
			var k = str(cx + dx) + "_" + str(cy + dy)
			if grafo.has(k):
				return grafo[k]
	return []


func _construir_grafo(ruas: Array) -> Dictionary:
	var grafo = {}
	for rua in ruas:
		var wps: PoolVector2Array = rua["wps"]
		if wps.size() < 2:
			continue
		# Rua percorrida da frente para trás (entrada pelo início)
		var k0 = _snap_key(wps[0])
		if not grafo.has(k0):
			grafo[k0] = []
		grafo[k0].append({"wps": wps, "oneway": rua["oneway"]})
		# Mão dupla: também pode ser percorrida do fim para a frente
		if not rua["oneway"]:
			var k1 = _snap_key(wps[wps.size() - 1])
			if not grafo.has(k1):
				grafo[k1] = []
			grafo[k1].append({"wps": _inverter(wps), "oneway": false})
	return grafo


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
