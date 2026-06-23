shader_type canvas_item;

// Posição do player em unidades pré-ESCALA (atualizada a cada frame)
uniform vec2 player_pos_pre = vec2(0.0, 0.0);

// Altura virtual da câmera em metros (menor = efeito mais dramático, faixa útil: 200–800)
// Formula GTA 2: offset = (player_pos - vertex_pos) * altura_m / cam_height
uniform float cam_height = 400.0;

// Cor do telhado (definida por tier ao criar o ShaderMaterial)
uniform vec4 vis_color = vec4(0.5, 0.5, 0.5, 1.0);

void vertex() {
    // VERTEX aqui está em pré-ESCALA absoluta
    // (visual.position = vec2(0) + WorldOSM scale=15 → VERTEX = polygon coords pré-ESCALA)
    float height_m = COLOR.r * 100.0;

    // Perspectiva GTA 2: telhado se inclina em direção ao player
    // Prédios mais distantes inclinam mais, como câmera real a cam_height metros de altura
    VERTEX += (player_pos_pre - VERTEX) * height_m / cam_height;
}

void fragment() {
    COLOR = vis_color;
}
