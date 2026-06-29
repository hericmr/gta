# map_features.gd — Gerencia e desenha as feições (features) do OSM do mapa de Santos (Mar, Canais, Parques, Praia)
extends Reference

class_name MapFeatures

const SHADER_MAR    = preload("res://scripts/water_sea.shader")
const SHADER_CANAL  = preload("res://scripts/water_canal.shader")
const TEX_NOISE     = preload("res://Textures/water_noise.png")
const TILE_GRAMA    = 35.0

# Cria todos os nós visuais das feições geográficas no nó pai especificado
static func criar_features(parent: Node2D, dados: Dictionary) -> void:
	var tex_agua = obter_textura_agua_procedural()

	# 1. Mar / Oceano Atlântico (z=-9) — abaixo da praia e dos jardins
	for f in dados.get("mar", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		var uvs  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
			uvs.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.uv      = uvs
		poly.texture = tex_agua
		
		var mat = ShaderMaterial.new()
		mat.shader = SHADER_MAR
		mat.set_shader_param("noise_texture", TEX_NOISE)
		poly.material = mat
		
		poly.color   = Color(1.0, 1.0, 1.0, 1.0)
		poly.z_index = -38
		parent.add_child(poly)

	# 2. Porto/industrial (z=-9, mesmo nível do mar mas adicionado depois → fica na frente)
	for f in dados.get("porto", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.color   = Color(0.38, 0.32, 0.28, 0.75)
		poly.z_index = -38
		parent.add_child(poly)

	# 3. Praia — areia (z=-8, adicionada antes do verde → verde (jardins) fica na frente)
	for f in dados.get("praia", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.color   = Color(0.87, 0.82, 0.62, 0.80)
		poly.z_index = -37
		parent.add_child(poly)

	# 4. Parques e jardins (z=-8) — textura de grama com tiling
	var tex_grama = obter_textura_grama_procedural()
	for f in dados.get("verde", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		var uvs  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
			uvs.append(Vector2(p[0] / TILE_GRAMA, p[1] / TILE_GRAMA))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.uv      = uvs
		poly.texture = tex_grama
		poly.color   = Color(1.0, 1.0, 1.0, 1.0)
		poly.z_index = -24
		parent.add_child(poly)

	# 5. Corpos d'água / Canais menores / Lagos — polígonos (z=-7)
	for f in dados.get("agua", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		var uvs  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
			uvs.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.uv      = uvs
		poly.texture = tex_agua
		
		var mat = ShaderMaterial.new()
		mat.shader = SHADER_MAR
		mat.set_shader_param("noise_texture", TEX_NOISE)
		poly.material = mat
		
		poly.color   = Color(1.0, 1.0, 1.0, 1.0)
		poly.z_index = -36
		parent.add_child(poly)

	# 6. Canais — linhas largas com fluxo longitudinal e bordas de concreto (z=-6)
	for c in dados.get("canais", []):
		var pts = c["pontos"]
		if pts.size() < 2:
			continue
		var linha = Line2D.new()
		var comprimento = 0.0
		var anterior = Vector2(pts[0][0], pts[0][1])
		linha.add_point(anterior)
		for i in range(1, pts.size()):
			var atual = Vector2(pts[i][0], pts[i][1])
			linha.add_point(atual)
			comprimento += anterior.distance_to(atual)
			anterior = atual
		
		var largura = c.get("largura", 15.0)
		var mat = ShaderMaterial.new()
		mat.shader = SHADER_CANAL
		mat.set_shader_param("canal_length", comprimento)
		mat.set_shader_param("canal_width", largura)
		mat.set_shader_param("noise_texture", TEX_NOISE)
		
		linha.material       = mat
		linha.texture        = tex_agua
		linha.texture_mode   = Line2D.LINE_TEXTURE_STRETCH
		linha.default_color  = Color(1.0, 1.0, 1.0, 1.0)
		linha.width          = largura
		linha.joint_mode     = Line2D.LINE_JOINT_ROUND
		linha.begin_cap_mode = Line2D.LINE_CAP_ROUND
		linha.end_cap_mode   = Line2D.LINE_CAP_ROUND
		linha.z_index        = -35
		parent.add_child(linha)

	print("[WorldOSM] Features carregadas via MapFeaturesBuilder: mar=%d porto=%d praia=%d verde=%d agua=%d canais=%d" % [
		len(dados.get("mar",    [])),
		len(dados.get("porto",  [])),
		len(dados.get("praia",  [])),
		len(dados.get("verde",  [])),
		len(dados.get("agua",   [])),
		len(dados.get("canais", []))])

# Gera a textura procedimental para a grama dos parques
static func obter_textura_grama_procedural() -> Texture:
	var img = Image.new()
	img.create(16, 16, false, Image.FORMAT_RGBA8)
	img.lock()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	# 1. Pinta o fundo com um verde escuro denso com leve ruído pixelado
	for x in range(16):
		for y in range(16):
			var r = rng.randf()
			var base_g = 0.18 + r * 0.05
			var c = Color(base_g * 0.5, base_g, base_g * 0.5, 1.0)
			img.set_pixel(x, y, c)
			
	# 2. Desenha pequenos tufos de grama em pixel art (verde médio e claro)
	var cor_tufo_escura = Color(0.12, 0.35, 0.12, 1.0)
	var cor_tufo_clara  = Color(0.20, 0.52, 0.20, 1.0)
	
	var tufos = [
		Vector2(3, 4),
		Vector2(11, 2),
		Vector2(6, 11),
		Vector2(13, 10)
	]
	
	for t in tufos:
		var tx = int(t.x)
		var ty = int(t.y)
		img.set_pixel(tx, ty, cor_tufo_clara)
		img.set_pixel((tx - 1 + 16) % 16, (ty + 1) % 16, cor_tufo_escura)
		img.set_pixel(tx, (ty + 1) % 16, cor_tufo_escura)
		img.set_pixel((tx + 1) % 16, (ty + 1) % 16, cor_tufo_escura)

	# 3. Desenha algumas folhas soltas
	var folhas = [
		Vector2(1, 1), Vector2(8, 2), Vector2(14, 5),
		Vector2(2, 9), Vector2(9, 8), Vector2(5, 14)
	]
	for f in folhas:
		img.set_pixel(int(f.x), int(f.y), cor_tufo_clara)
		
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT)
	return tex

# Gera a textura procedimental para a copa das árvores (vista de cima)
static func obter_textura_arvore_procedural() -> Texture:
	var img = Image.new()
	img.create(64, 64, false, Image.FORMAT_RGBA8)
	img.lock()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765
	
	var centro = Vector2(32, 32)
	var raio = 28.0
	var luz = Vector2(20, 20) # Fonte de luz simulada vindo do canto superior esquerdo
	
	for x in range(64):
		for y in range(64):
			var pos = Vector2(x, y)
			var d_centro = pos.distance_to(centro)
			
			if d_centro <= raio:
				var d_luz = pos.distance_to(luz)
				var t = clamp(d_luz / 48.0, 0.0, 1.0)
				
				# Gradiente verde base: de verde claro iluminado a verde escuro na sombra
				var cor_base = Color(0.20, 0.55, 0.20).linear_interpolate(Color(0.08, 0.25, 0.08), t)
				
				# Detalhes de folhas e folhagem usando ruído e ondas
				var noise = rng.randf() * 0.12 - 0.06
				var tuft = sin(d_centro * 0.4) * cos(atan2(y - 32, x - 32) * 5.0) * 0.06
				
				cor_base.r = clamp(cor_base.r + noise + tuft, 0.0, 1.0)
				cor_base.g = clamp(cor_base.g + noise + tuft, 0.0, 1.0)
				cor_base.b = clamp(cor_base.b + noise + tuft, 0.0, 1.0)
				
				# Suavização das bordas para anti-aliasing
				if d_centro > raio - 1.5:
					cor_base.a = clamp((raio - d_centro) / 1.5, 0.0, 1.0)
				else:
					cor_base.a = 1.0
					
				img.set_pixel(x, y, cor_base)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex

# Gera a textura procedimental para a sombra da árvore
static func obter_textura_sombra_procedural() -> Texture:
	var img = Image.new()
	img.create(64, 64, false, Image.FORMAT_RGBA8)
	img.lock()
	
	var centro = Vector2(32, 32)
	var raio = 28.0
	
	for x in range(64):
		for y in range(64):
			var pos = Vector2(x, y)
			var d_centro = pos.distance_to(centro)
			
			if d_centro <= raio:
				var alpha = 0.35
				if d_centro > raio - 3.0:
					alpha = 0.35 * clamp((raio - d_centro) / 3.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex

# Gera a textura procedimental para a água do mar e canais em pixel art
static func obter_textura_agua_procedural() -> Texture:
	var img = Image.new()
	img.create(32, 32, false, Image.FORMAT_RGBA8)
	img.lock()
	
	# Paleta clássica de água pixel art unificada
	var base_color = Color(0.12, 0.36, 0.64, 1.0) # Azul marinho profundo
	var wave_color = Color(0.18, 0.48, 0.76, 1.0) # Azul médio
	var foam_color = Color(0.50, 0.75, 0.95, 1.0) # Azul claro brilhante
	
	for x in range(32):
		for y in range(32):
			# Senos e cossenos combinados com frequências que se repetem a cada 32 pixels
			# garante um tiling 100% contínuo e sem emendas (seamless)
			var angle_x1 = x * (2.0 * PI / 32.0)
			var angle_y1 = y * (2.0 * PI / 32.0)
			var angle_x2 = x * (4.0 * PI / 32.0)
			var angle_y2 = y * (4.0 * PI / 32.0)
			
			# Função periódica para gerar um padrão de ondas orgânico
			var w = sin(angle_x1) * cos(angle_y1) + cos(angle_x2 + angle_y1) * sin(angle_y2) * 0.5
			
			var c = base_color
			# Cria contornos posterizados nítidos para simular o estilo pixel art
			if w > 0.38:
				c = foam_color
			elif w > 0.08:
				c = wave_color
				
			img.set_pixel(x, y, c)
			
	img.unlock()
	
	var tex = ImageTexture.new()
	# FLAG_REPEAT para que a textura possa ser rolada indefinidamente
	# FLAG_MIPMAPS desativado implicitamente para manter a nitidez do pixel art sem suavização
	tex.create_from_image(img, Texture.FLAG_REPEAT)
	return tex
