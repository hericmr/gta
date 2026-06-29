# minimapa.gd — Componente de Mini Mapa no HUD mostrando a cidade inteira (Godot 3 - Chunks de Lotes)
extends Control

const CAMINHO_JSON = "res://maps/santos.json"
const MAPA_LARG    = 8960.0
const MAPA_ALT     = 14848.0
const PADDING      = 4.0

var _player_pos = Vector2.ZERO
var _player_rot = 0.0
var _pulso = 0.0

var _s_e = 0.0
var _s_ox = 0.0
var _s_oy = 0.0

# Arrays de sub-lotes (PoolVector2Arrays de tamanho limitado a 1000 pontos)
# Isso contorna o limite físico de tamanho de buffer do sistema de batching do Godot 2D/OpenGL
var _chunks_normal = []
var _chunks_main   = []

func _ready() -> void:
	# 1. Calcula a escala ideal para encaixar o retângulo do mapa de Santos no Mini Mapa
	var area_y = 110.0 - PADDING * 2.0
	_s_e = area_y / MAPA_ALT
	var larg_desenhada = MAPA_LARG * _s_e
	_s_ox = (110.0 - larg_desenhada) / 2.0
	_s_oy = PADDING

	# 2. Carrega as ruas do JSON e pré-calcula subdividindo em chunks de 500 segmentos
	var arq = File.new()
	if arq.file_exists(CAMINHO_JSON):
		arq.open(CAMINHO_JSON, File.READ)
		var dados = parse_json(arq.get_as_text())
		arq.close()
		
		if dados and dados.has("ruas"):
			var chunk_normal = PoolVector2Array()
			var chunk_main   = PoolVector2Array()
			
			for rua in dados["ruas"]:
				var pts = rua["pontos"]
				if pts.size() < 2:
					continue
				
				var larg = float(rua.get("largura", 4.0))
				var is_main = (larg >= 8.0)
				
				for i in range(pts.size() - 1):
					var p1 = Vector2(pts[i][0] * _s_e + _s_ox, pts[i][1] * _s_e + _s_oy)
					var p2 = Vector2(pts[i+1][0] * _s_e + _s_ox, pts[i+1][1] * _s_e + _s_oy)
					
					if is_main:
						chunk_main.append(p1)
						chunk_main.append(p2)
						if chunk_main.size() >= 1000: # 500 segmentos lineares
							_chunks_main.append(chunk_main)
							chunk_main = PoolVector2Array()
					else:
						chunk_normal.append(p1)
						chunk_normal.append(p2)
						if chunk_normal.size() >= 1000: # 500 segmentos lineares
							_chunks_normal.append(chunk_normal)
							chunk_normal = PoolVector2Array()
			
			# Adiciona as sobras
			if chunk_main.size() > 0:
				_chunks_main.append(chunk_main)
			if chunk_normal.size() > 0:
				_chunks_normal.append(chunk_normal)
				
			print("[MiniMapa] Chunks criados: %d normais, %d principais" % [
				_chunks_normal.size(), _chunks_main.size()
			])

func atualizar(pos_jogo: Vector2, rot: float) -> void:
	_player_pos = pos_jogo
	_player_rot = rot
	update()

func _process(delta: float) -> void:
	_pulso += delta * 4.0

func _draw() -> void:
	# 1. Fundo Escuro Moderno (com borda)
	draw_rect(Rect2(0, 0, 110, 110), Color(0.08, 0.10, 0.14, 0.90))
	draw_rect(Rect2(0, 0, 110, 110), Color(1, 1, 1, 0.15), false, 2.0)
	
	# 2. Desenha as Ruas usando chamadas segmentadas seguras de loteamento
	var cor_rua_normal = Color(0.65, 0.70, 0.80, 0.95)   # Aumentada opacidade e brilho
	var cor_rua_main   = Color(1.0, 1.0, 1.0, 1.0)       # Sólido
	
	for chunk in _chunks_normal:
		draw_multiline(chunk, cor_rua_normal, 1.0)
		
	for chunk in _chunks_main:
		draw_multiline(chunk, cor_rua_main, 2.0)

	# 3. Desenha o Player (Bolinha pulsante vermelha)
	var player_pos_pre = _player_pos / 15.0
	var player_pos_tela = Vector2(player_pos_pre.x * _s_e + _s_ox, player_pos_pre.y * _s_e + _s_oy)
	
	# Círculo pulsante externo
	var raio_ext = 3.5 + sin(_pulso) * 1.5
	draw_circle(player_pos_tela, raio_ext, Color(1.0, 0.2, 0.2, 0.4))
	# Círculo sólido
	draw_circle(player_pos_tela, 2.5, Color(1.0, 0.15, 0.15, 1.0))
	# Ponto central branco
	draw_circle(player_pos_tela, 1.0, Color(1, 1, 1, 0.95))
