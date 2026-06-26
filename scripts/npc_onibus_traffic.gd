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


func _ready() -> void:
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
	for p in pontos:
		bruto.append(Vector2(p[0] * ESCALA, p[1] * ESCALA))
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
