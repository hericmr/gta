# mapa_desenho.gd — Control que delega _draw() para mapa.gd
extends Control

func _draw() -> void:
    get_parent().desenhar(self)
