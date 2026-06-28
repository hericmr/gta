# npc_pedestre.gd — Pedestre NPC com mesmo asset e tamanho do player (Godot 3)
extends KinematicBody2D

const DIST_WP  = 12.0
const FPS_ANIM = 8.0
const N_FRAMES = 5

# Variação de comportamento individual
const PAUSA_PROB     = 0.002   # chance/frame de parar (~1 vez/8 s a 60 fps)
const PAUSA_MIN      = 0.7
const PAUSA_MAX      = 2.5
const ESPERA_FIM_MIN = 3.0     # aguarda no destino antes de pedir nova rota
const ESPERA_FIM_MAX = 8.0

const TEX_WALK   = preload("res://assets/human/player_walk.png")
const TEX_MORTO  = preload("res://assets/human/SP_1111.png")
const TEX_SANGUE = preload("res://assets/human/SP_127.png")

# Combinações de roupa [camisa (topo), calça (base)]
const COMBINACOES = [
	[Color(0.95, 0.25, 0.25), Color(0.20, 0.20, 0.65)],  # vermelho + azul
	[Color(0.25, 0.50, 0.95), Color(0.12, 0.12, 0.12)],  # azul + preto
	[Color(0.20, 0.72, 0.25), Color(0.72, 0.55, 0.30)],  # verde + bege
	[Color(1.00, 0.88, 0.10), Color(0.22, 0.42, 0.18)],  # amarelo + verde escuro
	[Color(1.00, 0.55, 0.10), Color(0.30, 0.18, 0.08)],  # laranja + marrom
	[Color(0.78, 0.20, 0.78), Color(0.12, 0.12, 0.12)],  # roxo + preto
	[Color(0.90, 0.90, 0.90), Color(0.35, 0.25, 0.18)],  # branco + marrom
	[Color(0.50, 0.82, 0.92), Color(0.62, 0.62, 0.62)],  # azul claro + cinza
	[Color(0.55, 0.35, 0.20), Color(0.88, 0.83, 0.72)],  # marrom + bege
	[Color(0.15, 0.62, 0.55), Color(0.82, 0.28, 0.28)],  # teal + vermelho
]

var _wps:         PoolVector2Array = PoolVector2Array()
var _idx:         int    = 0
var _vel:         float  = 10.0
var _terminado:   bool   = false
var _frame_timer: float  = 0.0
var _frame_atual: int    = 0
var _sprite:      Sprite = null
var _sprite_topo: Sprite = null
var _morto:       bool   = false
var _cor_topo:    Color  = Color.white
var _cor_base:    Color  = Color.white
var _half_h:      float  = 0.0
var _pausa_t:          float  = 0.0
var _espera_t:         float  = 0.0
var _esperando_onibus: bool   = false
var no_onibus:         bool   = false
var recem_desembarcado: bool  = false
var _tempo_idle:       float  = 0.0
var _desvio_idle:      Vector2 = Vector2.ZERO
var _congelado:        bool   = false

signal chegou_ao_fim


func congelar() -> void:
	if _congelado or no_onibus:
		return
	_congelado      = true
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask  = 0


func descongelar() -> void:
	if not _congelado:
		return
	_congelado      = false
	set_physics_process(true)
	set_process(true)
	collision_layer = 8
	collision_mask  = 1


func _ready() -> void:
	add_to_group("pedestres")
	_half_h = TEX_WALK.get_size().y / 2.0
	_criar_sprites()
	_aplicar_combinacao()

	var shape = CircleShape2D.new()
	shape.radius = 7.9
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	collision_layer = 8
	collision_mask  = 1


func _criar_sprites() -> void:
	var tex_w = TEX_WALK.get_size().x

	# Parte inferior (calça) — metade de baixo da textura
	_sprite = Sprite.new()
	_sprite.texture        = TEX_WALK
	_sprite.hframes        = N_FRAMES
	_sprite.region_enabled = true
	_sprite.region_rect    = Rect2(0, _half_h, tex_w, _half_h)
	_sprite.scale          = Vector2(2.08, 1.85)
	_sprite.position       = Vector2(0.0, -2.0 + _half_h * 0.5 * 1.85)
	add_child(_sprite)

	# Parte superior (camisa) — metade de cima da textura
	_sprite_topo = Sprite.new()
	_sprite_topo.texture        = TEX_WALK
	_sprite_topo.hframes        = N_FRAMES
	_sprite_topo.region_enabled = true
	_sprite_topo.region_rect    = Rect2(0, 0, tex_w, _half_h)
	_sprite_topo.scale          = Vector2(2.08, 1.85)
	_sprite_topo.position       = Vector2(0.0, -2.0 - _half_h * 0.5 * 1.85)
	add_child(_sprite_topo)


func _aplicar_combinacao() -> void:
	var combo       = COMBINACOES[randi() % COMBINACOES.size()]
	_cor_topo       = combo[0]
	_cor_base       = combo[1]
	_sprite.modulate      = _cor_base
	_sprite_topo.modulate = _cor_topo


func atropelar() -> void:
	if _morto:
		return
	_tocar_som_morte()
	_morto     = true
	_terminado = true
	collision_layer = 0
	collision_mask  = 0
	if _sprite_topo:
		_sprite_topo.visible = false
	if _sprite:
		_sprite.region_enabled = false
		_sprite.texture  = TEX_MORTO
		_sprite.hframes  = 1
		_sprite.frame    = 0
		_sprite.position = Vector2.ZERO
		_sprite.scale    = Vector2(2.0, 2.0)
		_sprite.modulate = _cor_topo   # cadáver mantém a cor da camisa
	z_index = 2
	_sangue_pos    = position
	_sangue_timer  = 1.0


var _sangue_pos:   Vector2 = Vector2.ZERO
var _sangue_timer: float   = -1.0


func _process(delta: float) -> void:
	if _sangue_timer < 0.0:
		return
	_sangue_timer -= delta
	if _sangue_timer <= 0.0:
		_sangue_timer = -1.0
		_criar_mancha_sangue(_sangue_pos)


func _criar_mancha_sangue(pos: Vector2) -> void:
	if get_parent() == null:
		return
	var sangue = Sprite.new()
	sangue.texture  = TEX_SANGUE
	sangue.position = pos
	sangue.rotation = randf() * TAU
	sangue.scale    = Vector2(2.25, 2.25)
	sangue.z_index  = 1   # abaixo do cadáver (z=2) e dos veículos (z=5)
	get_parent().add_child(sangue)


func reinicializar(wps: PoolVector2Array, vel: float, start: int = 0) -> void:
	if _morto and get_parent():
		var corpo = Sprite.new()
		corpo.texture  = TEX_MORTO
		corpo.position = position
		corpo.rotation = rotation
		corpo.scale    = Vector2(2.0, 2.0)
		corpo.modulate = _cor_topo   # corpo estático com a cor do pedestre
		corpo.z_index  = 2
		get_parent().add_child(corpo)
	_morto = false
	collision_layer = 8
	collision_mask  = 1
	z_index = 0
	if _sprite:
		_sprite.region_enabled = true
		_sprite.texture        = TEX_WALK
		_sprite.hframes        = N_FRAMES
		_sprite.position       = Vector2(0.0, -2.0 + _half_h * 0.5 * 1.85)
		_sprite.scale          = Vector2(2.08, 1.85)
		_sprite.visible        = true
	if _sprite_topo:
		_sprite_topo.visible = true
	_aplicar_combinacao()
	inicializar(wps, vel, start)


func _aplicar_offset_lateral(wps: PoolVector2Array) -> PoolVector2Array:
	var n = wps.size()
	if n < 2:
		return wps
	var off = rand_range(-14.0, 14.0)
	var result = PoolVector2Array()
	for i in range(n):
		var perp: Vector2
		if i == 0:
			perp = (wps[1] - wps[0]).normalized().rotated(PI * 0.5)
		elif i == n - 1:
			perp = (wps[i] - wps[i - 1]).normalized().rotated(PI * 0.5)
		else:
			var d1 = (wps[i] - wps[i - 1]).normalized()
			var d2 = (wps[i + 1] - wps[i]).normalized()
			var m  = d1 + d2
			perp = (m.normalized() if m.length() > 0.01 else d1).rotated(PI * 0.5)
		result.append(wps[i] + perp * off)
	return result


func caminhar_para(destino_global: Vector2) -> void:
	_esperando_onibus = false
	var local_dest = get_parent().to_local(destino_global)
	_wps       = PoolVector2Array([local_dest])
	_idx       = 0
	_terminado = false
	_espera_t  = 0.0
	_pausa_t   = 0.0
	_tempo_idle = 0.0
	_desvio_idle = Vector2.ZERO


func inicializar(wps: PoolVector2Array, vel: float, start: int = 0) -> void:
	_esperando_onibus = false
	_wps         = _aplicar_offset_lateral(wps)
	_vel         = vel
	_terminado   = false
	_frame_atual = randi() % N_FRAMES
	_frame_timer = 0.0
	_pausa_t     = 0.0
	_espera_t    = rand_range(ESPERA_FIM_MIN, ESPERA_FIM_MAX)
	_tempo_idle  = 0.0
	_desvio_idle = Vector2.ZERO
	var sz = _wps.size()
	_idx = start if start < sz else (sz - 1 if sz > 0 else 0)
	if _idx < _wps.size():
		position = _wps[_idx]


func _physics_process(delta: float) -> void:
	if _morto:
		return

	if _esperando_onibus:
		_tempo_idle -= delta
		if _tempo_idle <= 0.0:
			_tempo_idle = rand_range(4.0, 10.0) # muda de posição a cada 4-10 segundos
			_desvio_idle = Vector2(rand_range(-35.0, 35.0), rand_range(-35.0, 35.0))
			
		if _desvio_idle != Vector2.ZERO:
			var alvo = _wps[_wps.size() - 1] + _desvio_idle
			var dir = alvo - position
			var dist = dir.length()
			if dist > 8.0:
				rotation = atan2(dir.y, dir.x) - PI * 0.5
				move_and_slide((dir / dist) * (_vel * 0.5))
				_frame_timer += delta
				if _frame_timer >= 1.0 / (FPS_ANIM * 0.5):
					_frame_timer -= 1.0 / (FPS_ANIM * 0.5)
					_frame_atual = (_frame_atual + 1) % N_FRAMES
					if _sprite: _sprite.frame = _frame_atual
					if _sprite_topo: _sprite_topo.frame = _frame_atual
			else:
				if _sprite: _sprite.frame = 0
				if _sprite_topo: _sprite_topo.frame = 0
				_desvio_idle = Vector2.ZERO
		else:
			if _sprite: _sprite.frame = 0
			if _sprite_topo: _sprite_topo.frame = 0
		return

	if _idx >= _wps.size():
		# Aguarda brevemente no destino antes de solicitar nova rota
		if _espera_t > 0.0:
			_espera_t -= delta
			if _sprite:     _sprite.frame = 0
			if _sprite_topo: _sprite_topo.frame = 0
			return
		if not _terminado:
			_terminado = true
			emit_signal("chegou_ao_fim")
		if _sprite:     _sprite.frame = 0
		if _sprite_topo: _sprite_topo.frame = 0
		return

	# Pausa aleatória mid-walk
	if _pausa_t > 0.0:
		_pausa_t -= delta
		if _sprite:     _sprite.frame = 0
		if _sprite_topo: _sprite_topo.frame = 0
		return

	var diff = _wps[_idx] - position
	var dist = diff.length()

	if dist < DIST_WP:
		_idx += 1
		return

	if randf() < PAUSA_PROB:
		_pausa_t = rand_range(PAUSA_MIN, PAUSA_MAX)
		return

	rotation = atan2(diff.y, diff.x) - PI * 0.5
	move_and_slide((diff / dist) * _vel)

	_frame_timer += delta
	if _frame_timer >= 1.0 / FPS_ANIM:
		_frame_timer -= 1.0 / FPS_ANIM
		_frame_atual  = (_frame_atual + 1) % N_FRAMES
		if _sprite:
			_sprite.frame = _frame_atual
		if _sprite_topo:
			_sprite_topo.frame = _frame_atual


func _tocar_som_morte() -> void:
	var stream = load("res://assets/sons/morte_mulher.mp3")
	if not stream:
		return
	if "loop" in stream:
		stream.loop = false
	var som = AudioStreamPlayer2D.new()
	som.stream = stream
	som.volume_db = 2.0
	som.global_position = global_position
	som.connect("finished", som, "queue_free")
	get_tree().current_scene.add_child(som)
	som.play()
