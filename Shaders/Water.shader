shader_type canvas_item;

// Textura de ruído (seamless) e parâmetros de movimento
uniform sampler2D noise_texture;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.2;
uniform vec2 direction = vec2(1.0, 0.5);

// Parâmetros de escala e distorção
uniform float noise_scale = 0.15;
uniform float wave_scale = 0.0625; // Escala da textura de água base (maior = pixels menores e mais tiling)
uniform float wave_strength = 0.5;  // Distorção em pixels
uniform float pixel_size = 1.0;     // Tamanho do pixel virtual para o pixel art (1.0 = pixel nativo, maior = mais retrô)

// Parâmetros do brilho (shimmer)
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
uniform float detail : hint_range(0.0, 1.0) = 0.35; // Threshold do brilho
uniform float brightness : hint_range(0.0, 2.0) = 1.2;

// Paleta de cores para o mar/lago
uniform vec4 shallow_color : hint_color = vec4(0.18, 0.48, 0.76, 1.0);
uniform vec4 deep_color    : hint_color = vec4(0.12, 0.36, 0.64, 1.0);
uniform vec4 shimmer_color : hint_color = vec4(0.50, 0.75, 0.95, 1.0);

varying vec2 world_pos;

void vertex() {
    world_pos = VERTEX;
}

void fragment() {
    // 1. Calcular direções de fluxo complementares para evitar padrões repetitivos
    vec2 dir1 = normalize(direction);
    vec2 dir2 = vec2(-dir1.y, dir1.x); // Direção ortogonal para o segundo ruído
    
    vec2 offset1 = dir1 * (TIME * flow_speed * 15.0);
    vec2 offset2 = dir2 * (TIME * flow_speed * 11.0); // Velocidades ligeiramente diferentes
    
    // 2. Fazer snapping das posições no grid de pixels ANTES da amostragem do ruído
    // Isso evita subpixel jitter ao mover a câmera ou a água
    vec2 snapped_pos1 = floor((world_pos + offset1) / pixel_size) * pixel_size;
    vec2 snapped_pos2 = floor((world_pos + offset2) / pixel_size) * pixel_size;
    
    // Converter para UVs do ruído
    vec2 noise_uv1 = snapped_pos1 * noise_scale;
    vec2 noise_uv2 = snapped_pos2 * noise_scale;
    
    // 3. Amostrar o ruído (compatível com GLES2/GLES3)
    float n1 = texture(noise_texture, noise_uv1).r;
    float n2 = texture(noise_texture, noise_uv2).r;
    
    // Mistura de ruído por multiplicação e soma para padrão orgânico de ondas
    float combined_noise = (n1 + n2) * 0.5;
    
    // 4. Calcular distorção pixel-perfect das coordenadas da textura base
    vec2 distortion = vec2(n1 - 0.5, n2 - 0.5) * wave_strength;
    vec2 snapped_distortion = floor(distortion / pixel_size) * pixel_size;
    
    // Aplicar distorção à posição de leitura da textura base
    vec2 base_pos = world_pos + snapped_distortion;
    
    // Tiling das duas camadas da textura base
    vec2 base_uv1 = (base_pos + offset1 * 0.2) * wave_scale;
    vec2 base_uv2 = (base_pos + offset2 * 0.2) * wave_scale;
    
    vec4 tex1 = texture(TEXTURE, base_uv1);
    vec4 tex2 = texture(TEXTURE, base_uv2);
    
    // Otimização de performance: substituir 'if' por 'step' + 'mix' para evitar branch no GPU
    float m = step(tex1.r, tex2.r);
    vec4 final_color = mix(tex1, tex2, m);
    
    // Se a cor final for muito escura, mesclamos com o gradiente de profundidade
    // (Aumenta o contraste entre águas rasas/profundas)
    float depth_factor = clamp(combined_noise * 1.2, 0.0, 1.0);
    vec4 depth_color_mix = mix(deep_color, shallow_color, depth_factor);
    final_color.rgb = mix(depth_color_mix.rgb, final_color.rgb, 0.7);
    
    // 5. Aplicar brilho (shimmer) utilizando smoothstep e o ruído combinado
    // Mapeamos o parâmetro detail de forma que valores maiores gerem mais pontos de brilho
    float shimmer_threshold = 1.0 - detail;
    float shimmer = smoothstep(shimmer_threshold, shimmer_threshold + 0.1, combined_noise);
    
    // Mesclar a cor base com o brilho ajustado pela opacidade e intensidade
    final_color.rgb = mix(final_color.rgb, shimmer_color.rgb * brightness, shimmer * opacity);
    
    COLOR = final_color;
}
