# satelite_stream.gd — Carrega tiles de satélite dinamicamente (Godot 3)
# Desktop: Image.load() direto do disco
# HTML5:   HTTPRequest para buscar tiles do servidor (GitHub Pages)
extends Node2D

const ZOOM      = 18
const TILE_PX   = 256
const RAIO      = 4
const ESCALA    = 15.0
const MAX_HTTP  = 6    # requests HTTP simultâneos (HTML5)

var _tiles             = {}
var _meta              = {}
var _base              = ""
var _carro             = null
var _tile_anterior     = Vector2(-9999, -9999)

# HTML5: fila e pool de HTTPRequest
var _fila_http:   Array      = []
var _http_pool:   Array      = []
var _http_em_uso: Dictionary = {}   # HTTPRequest → chave "tx_ty"

# Valores derivados do meta
var _min_lat = 0.0
var _min_lon = 0.0
var _max_lat = 0.0
var _max_lon = 0.0
var _larg_px = 0
var _alt_px  = 0


func inicializar(carro, meta: Dictionary, caminho_base: String) -> void:
	_carro = carro
	_meta  = meta
	_base  = caminho_base

	var bbox = meta["bbox"]
	_min_lat = bbox[0]; _min_lon = bbox[1]
	_max_lat = bbox[2]; _max_lon = bbox[3]
	_larg_px = meta["largura_map_px"]
	_alt_px  = meta["altura_map_px"]

	if _base.begins_with("http"):
		for _i in range(MAX_HTTP):
			var req = HTTPRequest.new()
			add_child(req)
			_http_pool.append(req)

	set_process(true)


func _process(_delta) -> void:
	if _carro == null:
		return

	var pos = _carro.position / ESCALA
	var lat = _pos_para_lat(pos.y)
	var lon = _pos_para_lon(pos.x)
	var tc  = _ll_para_tile(lat, lon)

	if tc.distance_to(_tile_anterior) >= 0.5:
		_tile_anterior = tc
		_atualizar_tiles(int(tc.x), int(tc.y))

	_despachar_fila_http()


func _atualizar_tiles(tx_c: int, ty_c: int) -> void:
	var necessarios = {}
	for dy in range(-RAIO, RAIO + 1):
		for dx in range(-RAIO, RAIO + 1):
			var tx = tx_c + dx
			var ty = ty_c + dy
			if tx >= _meta["tx_min"] and tx <= _meta["tx_max"] \
			and ty >= _meta["ty_min"] and ty <= _meta["ty_max"]:
				necessarios[str(tx) + "_" + str(ty)] = Vector2(tx, ty)

	for chave in _tiles.keys():
		if not necessarios.has(chave):
			_tiles[chave].queue_free()
			_tiles.erase(chave)

	for chave in necessarios.keys():
		if not _tiles.has(chave):
			var v = necessarios[chave]
			_carregar_tile(int(v.x), int(v.y))


# ── Carregamento ──────────────────────────────────────────────────────────────

func _carregar_tile(tx: int, ty: int) -> void:
	var chave = str(tx) + "_" + str(ty)
	if _tiles.has(chave):
		return

	if _base.begins_with("http"):
		# HTML5: enfileira para buscar via HTTP
		for item in _fila_http:
			if item.tx == tx and item.ty == ty:
				return   # já na fila
		_fila_http.append({"tx": tx, "ty": ty})
		return

	# Desktop: lê direto do disco
	var arquivo = _base + ("z%d_%d_%d.png" % [ZOOM, tx, ty])
	var img = Image.new()
	if img.load(ProjectSettings.globalize_path(arquivo)) != OK:
		return
	var it = ImageTexture.new()
	it.create_from_image(img, 0)
	_criar_sprite(tx, ty, it)


func _despachar_fila_http() -> void:
	if _fila_http.empty():
		return
	for req in _http_pool:
		if _fila_http.empty():
			return
		if _http_em_uso.has(req):
			continue
		var item = _fila_http.pop_front()
		var url  = _base + ("z%d_%d_%d.png" % [ZOOM, item.tx, item.ty])
		_http_em_uso[req] = str(item.tx) + "_" + str(item.ty)
		req.connect("request_completed", self, "_on_tile_http",
				[req, item.tx, item.ty], CONNECT_ONESHOT)
		req.request(url)


func _on_tile_http(_result, code, _headers, body, req, tx, ty) -> void:
	_http_em_uso.erase(req)
	if code != 200 or body.size() == 0:
		return
	var img = Image.new()
	if img.load_png_from_buffer(body) != OK:
		return
	var it = ImageTexture.new()
	it.create_from_image(img, 0)
	_criar_sprite(tx, ty, it)


func _criar_sprite(tx: int, ty: int, tex: Texture) -> void:
	var chave = str(tx) + "_" + str(ty)
	if _tiles.has(chave):
		return
	var sprite        = Sprite.new()
	sprite.texture    = tex
	sprite.centered   = false
	sprite.position   = _tile_para_pos(tx, ty)
	var esc           = _tile_size_game() / float(TILE_PX)
	sprite.scale      = Vector2(esc, esc)
	sprite.z_index    = -45
	add_child(sprite)
	_tiles[chave]     = sprite


# ── Conversões geográficas ────────────────────────────────────────────────────

func _ll_para_tile(lat: float, lon: float) -> Vector2:
	var n  = pow(2.0, ZOOM)
	var tx = int((lon + 180.0) / 360.0 * n)
	var lr = deg2rad(lat)
	var ty = int((1.0 - log(tan(lr) + 1.0 / cos(lr)) / PI) / 2.0 * n)
	return Vector2(tx, ty)

func _tile_para_ll(tx: int, ty: int) -> Vector2:
	var n   = pow(2.0, ZOOM)
	var lon = float(tx) / n * 360.0 - 180.0
	var lat = rad2deg(atan(sinh(PI * (1.0 - 2.0 * float(ty) / n))))
	return Vector2(lat, lon)

func _geo_para_game(lat: float, lon: float) -> Vector2:
	var x = (lon - _min_lon) / (_max_lon - _min_lon) * float(_larg_px)
	var y = (1.0 - (lat - _min_lat) / (_max_lat - _min_lat)) * float(_alt_px)
	return Vector2(x, y)

func _tile_para_pos(tx: int, ty: int) -> Vector2:
	var ll = _tile_para_ll(tx, ty)
	return _geo_para_game(ll.x, ll.y)

func _pos_para_lat(y_pre: float) -> float:
	var frac = 1.0 - y_pre / float(_alt_px)
	return _min_lat + frac * (_max_lat - _min_lat)

func _pos_para_lon(x_pre: float) -> float:
	return _min_lon + (x_pre / float(_larg_px)) * (_max_lon - _min_lon)

func _tile_size_game() -> float:
	var lon_por_tile = 360.0 / pow(2.0, ZOOM)
	return lon_por_tile / (_max_lon - _min_lon) * float(_larg_px)
