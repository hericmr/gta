shader_type canvas_item;

uniform float speed = 0.5;
uniform float wave_scale = 0.015625; // 1.0 / (32 texels * 2.0 scale) = 0.015625

varying vec2 world_pos;

void vertex() {
    world_pos = VERTEX;
}

void fragment() {
    // Escala e centralização baseada no mundo para tiling sem costuras
    vec2 pos = world_pos * wave_scale;
    
    // Duas camadas de textura de água rolando em direções diferentes
    vec2 uv1 = pos + vec2(TIME * speed * 0.05, TIME * speed * 0.03);
    vec2 uv2 = pos + vec2(-TIME * speed * 0.03, TIME * speed * 0.04);
    
    // Amostra a textura do Polygon2D
    vec4 tex1 = texture(TEXTURE, uv1);
    vec4 tex2 = texture(TEXTURE, uv2);
    
    // Mescla as duas texturas para criar ondas orgânicas pixeladas
    // Usa o canal vermelho como comparação de brilho para misturar
    vec4 final_color = tex1;
    if (tex2.r > tex1.r) {
        final_color = tex2;
    }
    
    COLOR = final_color;
}
