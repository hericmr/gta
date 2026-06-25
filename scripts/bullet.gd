# bullet.gd — Projétil do player (Area2D — Godot 3)
extends Area2D

const VEL      = 1000.0
const MAX_DIST = 1800.0

var _dir:  Vector2 = Vector2.ZERO
var _dist: float   = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask  = 8    # layer 4 (pedestres)
	monitoring  = true
	monitorable = false
	connect("body_entered", self, "_on_body")

	# Traço visual (cauda atrás do projétil)
	var linha = Line2D.new()
	linha.add_point(Vector2(0, -5))
	linha.add_point(Vector2(0, 0))
	linha.width         = 5.0
	linha.default_color = Color(0, 0, 0)
	linha.z_index       = 5
	add_child(linha)

	var shape = CircleShape2D.new()
	shape.radius = 8.0
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func iniciar(direcao: Vector2) -> void:
	_dir     = direcao.normalized()
	rotation = atan2(_dir.y, _dir.x) - PI * 0.5


func _physics_process(delta: float) -> void:
	position += _dir * VEL * delta
	_dist    += VEL * delta
	if _dist > MAX_DIST:
		queue_free()


func _on_body(body) -> void:
	if body.is_in_group("pedestres") and not body._morto:
		body.atropelar()
		get_tree().call_group("hud", "registrar_atropelamento")
	queue_free()
