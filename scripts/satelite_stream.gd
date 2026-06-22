# satelite_stream.gd — Carrega tiles de satélite dinamicamente conforme o carro se move
# Cada tile é carregado do disco via Image.load() — sem passar pelo sistema de import do Godot
extends Node2D

const ZOOM    = 18
const TILE_PX = 256
const RAIO    = 4    # tiles carregados ao redor do jogador (RAIO×2+1)²
const ESCALA  = 15.0 # deve bater com world_osm.gd

# Chave: "tx_ty" → Sprite
var _tiles   = {}
var _meta    = {}
var _base    = ""    # caminho absoluto para assets/tiles/
var _carro   = null
var _tile_anterior = Vector2(-9999, -9999)

# Valores derivados do meta (calculados uma vez)
var _min_lat  = 0.0
var _min_lon  = 0.0
var _max_lat  = 0.0
var _max_lon  = 0.0
var _larg_px  = 0
var _alt_px   = 0


func inicializar(carro, meta: Dictionary, caminho_base: String) -> void:
	_carro = carro
	_meta  = meta
	_base  = caminho_base

	var bbox  = meta["bbox"]
	_min_lat  = bbox[0]; _min_lon = bbox[1]
	_max_lat  = bbox[2]; _max_lon = bbox[3]
	_larg_px  = meta["largura_map_px"]
	_alt_px   = meta["altura_map_px"]

	set_process(true)


func _process(_delta) -> void:
	if _carro == null:
		return

	# Posição do carro em coordenadas pré-ESCALA
	var pos = _carro.position / ESCALA

	# Converte posição para lat/lon e depois para índice de tile
	var lat = _pos_para_lat(pos.y)
	var lon = _pos_para_lon(pos.x)
	var tc  = _ll_para_tile(lat, lon)

	if tc.distance_to(_tile_anterior) < 0.5:
		return
	_tile_anterior = tc

	_atualizar_tiles(int(tc.x), int(tc.y))


func _atualizar_tiles(tx_center: int, ty_center: int) -> void:
	# Monta conjunto de tiles necessários
	var necessarios = {}
	for dy in range(-RAIO, RAIO + 1):
		for dx in range(-RAIO, RAIO + 1):
			var tx = tx_center + dx
			var ty = ty_center + dy
			# Só carrega se está dentro do range baixado
			if tx >= _meta["tx_min"] and tx <= _meta["tx_max"] \
			and ty >= _meta["ty_min"] and ty <= _meta["ty_max"]:
				necessarios[str(tx) + "_" + str(ty)] = Vector2(tx, ty)

	# Remove tiles distantes
	for chave in _tiles.keys():
		if not necessarios.has(chave):
			_tiles[chave].queue_free()
			_tiles.erase(chave)

	# Carrega tiles novos
	for chave in necessarios.keys():
		if not _tiles.has(chave):
			var tc2 = necessarios[chave]
			_carregar_tile(int(tc2.x), int(tc2.y))


func _carregar_tile(tx: int, ty: int) -> void:
	var arquivo = _base + ("z%d_%d_%d.png" % [ZOOM, tx, ty])

	var tex = load(arquivo)
	if tex == null:
		return   # tile não disponível no .pck

	var sprite = Sprite.new()
	sprite.texture  = tex
	sprite.centered = false
	sprite.position = _tile_para_pos(tx, ty)
	# Escala o tile de px-de-imagem para unidades pré-ESCALA
	var escala_tile = _tile_size_game() / float(TILE_PX)
	sprite.scale    = Vector2(escala_tile, escala_tile)
	sprite.z_index  = -10

	add_child(sprite)
	_tiles[str(tx) + "_" + str(ty)] = sprite


# ── Conversões geográficas ─────────────────────────────────────────────────

func _ll_para_tile(lat: float, lon: float) -> Vector2:
	var n  = pow(2.0, ZOOM)
	var tx = int((lon + 180.0) / 360.0 * n)
	var lr = deg2rad(lat)
	var ty = int((1.0 - log(tan(lr) + 1.0 / cos(lr)) / PI) / 2.0 * n)
	return Vector2(tx, ty)

func _tile_para_ll(tx: int, ty: int) -> Vector2:
	# Retorna lat/lon do canto superior-esquerdo do tile
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
	# Tamanho de 1 tile em unidades pré-ESCALA (pelo eixo longitude)
	var lon_por_tile = 360.0 / pow(2.0, ZOOM)
	return lon_por_tile / (_max_lon - _min_lon) * float(_larg_px)
