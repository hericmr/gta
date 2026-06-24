# hud.gd — Velocímetro com debug de velocidade real (Godot 3)
extends CanvasLayer

# metros por game unit — derivado do meta.json atual
const M_POR_GAME_UNIT = 0.03638

onready var _label:       Label = $Control/LabelVel
onready var _label_debug: Label = $Control/LabelDebug

var _pos_anterior: Vector2 = Vector2.ZERO
var _ref_node = null   # recebe referência do main.gd


func atualizar_velocidade(kmh: float) -> void:
	_label.text = "%d km/h" % int(kmh)


func definir_ref(no) -> void:
	_ref_node  = no
	_pos_anterior = no.position


func _process(delta: float) -> void:
	if _ref_node == null or delta <= 0.0:
		return
	var deslocamento_units = _ref_node.position.distance_to(_pos_anterior) / delta
	_pos_anterior = _ref_node.position
	var kmh_real = deslocamento_units * M_POR_GAME_UNIT * 3.6
	_label_debug.text = "real: %d km/h" % int(kmh_real)
