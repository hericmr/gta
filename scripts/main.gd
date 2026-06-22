# main.gd — Cena raiz: conecta sinais e passa referências (Godot 3)
extends Node2D

var _stream = null
var _debug_t = 0.0

func _ready() -> void:
	var carro = $Car
	var hud   = $HUD
	var mundo = $World

	carro.connect("velocidade_mudou", hud, "atualizar_velocidade")

	if mundo.has_meta("satelite_stream"):
		_stream = mundo.get_meta("satelite_stream")
		_stream._carro = carro

	# Spawn: lat=-23.984451, lon=-46.308218
	carro.position = Vector2(90672.0, 109801.3)

func _process(delta: float) -> void:
	_debug_t += delta
	if _debug_t < 1.0 or _stream == null:
		return
	_debug_t = 0.0

	var pos = $Car.position / 15.0  # divide por ESCALA para coords pré-escala
	var lat = _stream._pos_para_lat(pos.y)
	var lon = _stream._pos_para_lon(pos.x)
	print("[CAR] lat=%.6f  lon=%.6f" % [lat, lon])
