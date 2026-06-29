# npc_onibus_traffic.gd — Gerencia ônibus NPC nas rotas reais de Santos (Godot 3)
extends Node2D

const NpcOnibusScript = preload("res://scripts/npc_onibus.gd")

const ESCALA            = 15.0
var N_ONIBUS: int = 60
const DIST_PARADA_WP    = 300.0  # raio (px) para associar parada ao waypoint mais próximo
const MIN_WPS           = 2     # rota com menos pontos é ignorada

const URL_LINHAS = "https://hericmr.github.io/gta/newdata/linhas_onibus.json"

var _linhas: Array = []   # [{wps_ida, wps_volta, par_ida, par_volta}]
var _onibus: Array = []
var _ref           = null
var _ruas_grid: Dictionary = {}


func _ready() -> void:
	if OS.has_touchscreen_ui_hint():
		N_ONIBUS = 20

	if OS.get_name() == "HTML5":
		var req = HTTPRequest.new()
		add_child(req)
		req.connect("request_completed", self, "_on_json_carregado")
		req.request(URL_LINHAS)
	else:
		_carregar_linhas()


func definir_ref(no) -> void:
	_ref = no
	if _onibus.empty() and not _linhas.empty():
		_spawnar_todos()


func _on_json_carregado(_result, code, _headers, body) -> void:
	if code != 200:
		push_warning("[Onibus] Falha HTTP (code=%d)" % code)
		return
	var dados = parse_json(body.get_string_from_utf8())
	if dados:
		_processar_linhas(dados)


func _carregar_linhas() -> void:
	var arq = File.new()
	var caminho = "res://newdata/linhas_onibus.json"
	if not arq.file_exists(caminho):
		push_warning("[Onibus] linhas_onibus.json não encontrado em res://newdata/")
		return
	arq.open(caminho, File.READ)
	var dados = parse_json(arq.get_as_text())
	arq.close()
	if dados:
		_processar_linhas(dados)


func _processar_linhas(dados: Dictionary) -> void:
	_construir_grid_ruas()
	for linha in dados.get("linhas", []):
		var wps_ida   = _to_wps(linha.get("percurso_ida_px",   []))
		var wps_volta = _to_wps(linha.get("percurso_volta_px", []))
		var paradas   = linha.get("paradas_px", [])

		if wps_ida.size() < MIN_WPS:
			continue

		var par_ida   = _mapear_paradas(wps_ida,   paradas)
		var par_volta = _mapear_paradas(wps_volta, paradas) if wps_volta.size() >= MIN_WPS else []

		_linhas.append({
			"wps_ida":   wps_ida,
			"wps_volta": wps_volta,
			"par_ida":   par_ida,
			"par_volta": par_volta,
		})

	print("[Onibus] %d linhas carregadas" % _linhas.size())
	if _ref != null:
		_spawnar_todos()


const PASSO_INTERPOLACAO = 280.0   # px máximos entre waypoints consecutivos

func _to_wps(pontos: Array) -> PoolVector2Array:
	var bruto = PoolVector2Array()
	var traffic = get_parent().get_node_or_null("NpcTraffic")
	var ruas = traffic._ruas_carro if (traffic and "_ruas_carro" in traffic) else []

	for p in pontos:
		var pos = Vector2(p[0] * ESCALA, p[1] * ESCALA)
		if not ruas.empty():
			pos = _ajustar_ponto_na_rua(pos, ruas)
		bruto.append(pos)
	return _interpolar(bruto)


# Insere waypoints intermediários para que nenhum salto ultrapasse PASSO_INTERPOLACAO.
# O ônibus ainda vai em linha reta entre pontos GPS, mas em passos curtos,
# permitindo que o move_and_slide contorne obstáculos gradualmente.
func _interpolar(wps: PoolVector2Array) -> PoolVector2Array:
	var result = PoolVector2Array()
	if wps.size() == 0:
		return result
	result.append(wps[0])
	for i in range(1, wps.size()):
		var a = wps[i - 1]
		var b = wps[i]
		var dist = a.distance_to(b)
		if dist > PASSO_INTERPOLACAO:
			var n: int = int(dist / PASSO_INTERPOLACAO)
			for j in range(1, n + 1):
				result.append(a.linear_interpolate(b, float(j) / float(n)))
		result.append(b)
	return result


func _mapear_paradas(wps: PoolVector2Array, paradas: Array) -> Array:
	var indices = []
	for parada in paradas:
		var px = Vector2(parada["x"] * ESCALA, parada["y"] * ESCALA)
		var melhor_idx  = -1
		var melhor_dist = DIST_PARADA_WP
		for i in range(wps.size()):
			var d = wps[i].distance_to(px)
			if d < melhor_dist:
				melhor_dist = d
				melhor_idx  = i
		if melhor_idx >= 0 and not indices.has(melhor_idx):
			indices.append(melhor_idx)
	indices.sort()
	return indices


func _spawnar_todos() -> void:
	# Distribui N_ONIBUS ônibus pelas linhas disponíveis: vários por linha
	for i in range(N_ONIBUS):
		var linha_idx = i % _linhas.size()
		# Índice do ônibus dentro da mesma linha (0, 1, 2…)
		var onibus_na_linha = i / _linhas.size()
		_spawnar_onibus(linha_idx, onibus_na_linha)

	print("[Onibus] %d ônibus spawnados em %d linhas" % [N_ONIBUS, _linhas.size()])


func _spawnar_onibus(linha_idx: int, onibus_na_linha: int = 0) -> void:
	var linha = _linhas[linha_idx]
	var wps   = linha["wps_ida"]
	var par   = linha["par_ida"]

	var onibus = NpcOnibusScript.new()
	add_child(onibus)

	# Distribui ônibus da mesma linha em pontos equidistantes da rota
	var qtd_por_linha: int = N_ONIBUS / _linhas.size() + 1
	var start: int = 0
	if wps.size() > 1 and qtd_por_linha > 0:
		start = onibus_na_linha * wps.size() / qtd_por_linha

	onibus.inicializar(wps, par, start)
	onibus.connect("chegou_ao_fim", self, "_on_fim_onibus", [onibus, linha_idx, true])
	_onibus.append(onibus)


func _on_fim_onibus(onibus, linha_idx: int, era_ida: bool) -> void:
	if not is_instance_valid(onibus):
		return

	var linha = _linhas[linha_idx]

	# Alterna entre ida e volta; se não houver volta, repete a ida
	var wps: PoolVector2Array
	var par: Array
	var proxima_ida: bool

	if era_ida and linha["wps_volta"].size() >= MIN_WPS:
		wps         = linha["wps_volta"]
		par         = linha["par_volta"]
		proxima_ida = false
	else:
		wps         = linha["wps_ida"]
		par         = linha["par_ida"]
		proxima_ida = true

	onibus.disconnect("chegou_ao_fim", self, "_on_fim_onibus")
	onibus.inicializar(wps, par, 0)
	onibus.connect("chegou_ao_fim", self, "_on_fim_onibus", [onibus, linha_idx, proxima_ida])


# ── Alinhamento de Rota GPS à Rede de Vias ────────────────────────────────────

func _construir_grid_ruas() -> void:
	_ruas_grid.clear()
	var traffic = get_parent().get_node_or_null("NpcTraffic")
	var ruas = traffic._ruas_carro if (traffic and "_ruas_carro" in traffic) else []
	if ruas.empty():
		return
	for r in ruas:
		var wps = r["wps"]
		if wps.empty():
			continue
		var min_x = 999999.0
		var max_x = -999999.0
		var min_y = 999999.0
		var max_y = -999999.0
		for pt in wps:
			if pt.x < min_x: min_x = pt.x
			if pt.x > max_x: max_x = pt.x
			if pt.y < min_y: min_y = pt.y
			if pt.y > max_y: max_y = pt.y
		var cell_x_min = int((min_x - 450.0) / 1000.0)
		var cell_x_max = int((max_x + 450.0) / 1000.0)
		var cell_y_min = int((min_y - 450.0) / 1000.0)
		var cell_y_max = int((max_y + 450.0) / 1000.0)
		for cx in range(cell_x_min, cell_x_max + 1):
			for cy in range(cell_y_min, cell_y_max + 1):
				var key = str(cx) + "_" + str(cy)
				if not _ruas_grid.has(key):
					_ruas_grid[key] = []
				_ruas_grid[key].append(r)


func _ajustar_ponto_na_rua(p: Vector2, _ruas_original: Array) -> Vector2:
	var key = str(int(p.x / 1000.0)) + "_" + str(int(p.y / 1000.0))
	var ruas_candidatas = _ruas_grid.get(key, [])
	if ruas_candidatas.empty():
		return p

	var melhor_p = p
	var melhor_dist = 999999.0
	for rua in ruas_candidatas:
		var wps = rua["wps"]
		for i in range(1, wps.size()):
			var s1 = wps[i - 1]
			var s2 = wps[i]
			var pt = Geometry.get_closest_point_to_segment_2d(p, s1, s2)
			var dist = p.distance_squared_to(pt)
			if dist < melhor_dist:
				melhor_dist = dist
				melhor_p = pt
				
	# Só ajusta se a rua estiver dentro de um raio de 450 pixels (~30m)
	# para evitar saltos bruscos se o traçado GPS estiver fora da rede de ruas
	if melhor_dist < 450.0 * 450.0:
		return melhor_p
	return p
