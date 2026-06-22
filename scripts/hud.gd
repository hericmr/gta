# hud.gd — Exibe o velocímetro na tela (Godot 3)
extends CanvasLayer

onready var _label: Label = $Control/LabelVel

func atualizar_velocidade(kmh) -> void:
	_label.text = "%d km/h" % int(kmh)
