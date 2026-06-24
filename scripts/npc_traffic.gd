# npc_traffic.gd — Pool de carros NPC que percorrem as ruas (Godot 3)
extends Node2D

const ESCALA       = 15.0
const N_CARROS     = 20
const RAIO_SPAWN   = 5000.0
const RAIO_DESPAWN = 7500.0
const VEL_MIN      = 250.0   # game units/s ≈ 33 km/h
const VEL_MAX      = 530.0   # game units/s ≈ 70 km/h
const MIN_PTS      = 4       # pontos mínimos para considerar a rua

var _ruas:   Array = []   # Array de PoolVector2Array (game coords)
var _carros: Array = []
var _ref           = null  # nó do veículo ativo (player ou carro)


func _ready() -> void:
	_carregar_ruas()


func definir_ref(no) -> void:
	_ref = no
	if _carros.empty() and not _ruas.empty():
		_spawnar_todos()


func _carregar_ruas() -> void:
	var arq = File.new()
	if not arq.file_exists("res://maps/santos.json"):
		push_warning("[Traffic] santos.json não encontrado")
		return
	arq.open("res://maps/santos.json", File.READ)
	var d = parse_json(arq.get_as_text())
	arq.close()
	for rua in d.get("ruas", []):
		var pts = rua["pontos"]
		if len(pts) < MIN_PTS:
			continue
		var arr = PoolVector2Array()
		for p in pts:
			arr.append(Vector2(p[0] * ESCALA, p[1] * ESCALA))
		_ruas.append(arr)
	print("[Traffic] %d ruas carregadas" % _ruas.size())


func _process(_delta: float) -> void:
	if _ref == null or _ruas.empty():
		return
	for carro in _carros:
		if is_instance_valid(carro) and \
		   carro.position.distance_to(_ref.position) > RAIO_DESPAWN:
			_resetar(carro)


func _spawnar_todos() -> void:
	for _i in range(N_CARROS):
		var c = _criar_carro()
		if c:
			_carros.append(c)


func _criar_carro():
	var wps = _wps_aleatorios()
	if wps.empty():
		return null
	var c = load("res://scripts/npc_car.gd").new()
	add_child(c)
	var vel   = lerp(VEL_MIN, VEL_MAX, randf())
	var start = randi() % wps.size()
	c.inicializar(wps, vel, start)
	c.connect("chegou_ao_fim", self, "_on_fim", [c])
	return c


func _resetar(carro) -> void:
	var wps = _wps_aleatorios()
	if wps.empty():
		return
	var vel = lerp(VEL_MIN, VEL_MAX, randf())
	carro.inicializar(wps, vel, 0)


func _on_fim(carro) -> void:
	if is_instance_valid(carro):
		_resetar(carro)


func _wps_aleatorios() -> PoolVector2Array:
	if _ruas.empty():
		return PoolVector2Array()

	var rua = PoolVector2Array()
	var encontrou = false

	if _ref != null:
		for _t in range(40):
			var r: PoolVector2Array = _ruas[randi() % _ruas.size()]
			# verifica se o ponto central da rua está dentro do raio
			var meio = r[r.size() / 2]
			if meio.distance_to(_ref.position) < RAIO_SPAWN:
				rua = r
				encontrou = true
				break

	if not encontrou:
		rua = _ruas[randi() % _ruas.size()]

	# Inverte 50% das vezes para simular tráfego nos dois sentidos
	if randi() % 2 == 0:
		var inv = PoolVector2Array()
		for i in range(rua.size() - 1, -1, -1):
			inv.append(rua[i])
		return inv
	return rua
