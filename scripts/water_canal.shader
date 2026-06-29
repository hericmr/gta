shader_type canvas_item;

// Parâmetros de cor originais
uniform vec4 shallow_color : hint_color = vec4(0.18, 0.48, 0.76, 1.0); // Azul claro nas bordas
uniform vec4 deep_color    : hint_color = vec4(0.12, 0.36, 0.64, 1.0); // Azul escuro no centro
uniform vec4 glow_color    : hint_color = vec4(0.50, 0.75, 0.95, 1.0); // Espuma/Glow nas margens
uniform vec4 wave_color    : hint_color = vec4(0.15, 0.42, 0.70, 1.0); // Onda estática intermediária original

// Parâmetros de dimensão originais
uniform float canal_length = 100.0;  // Comprimento em pixels
uniform float canal_width = 24.0;    // Largura em pixels (espessura da linha)
uniform float pixel_size = 1.0;      // Tamanho do pixel virtual (escala 1x)

// --- NOVOS Parâmetros do Shader Shimmering ---
uniform sampler2D noise_texture;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.15;
uniform vec2 direction = vec2(1.0, 0.0); // O fluxo do canal é longitudinal (ao longo de pos_x)
uniform float noise_scale = 0.15;
uniform float wave_scale = 0.0625; // Escala da textura de água base (maior = pixels menores)
uniform float wave_strength = 0.5; // Distorção de onda em pixels
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
uniform float detail : hint_range(0.0, 1.0) = 0.35;
uniform float brightness : hint_range(0.0, 2.0) = 1.2;
uniform vec4 shimmer_color : hint_color = vec4(0.50, 0.75, 0.95, 1.0);

varying vec2 world_pos;

void vertex() {
    world_pos = VERTEX;
}

// Função de hash pseudo-aleatória para manchas do concreto
float hash2d(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    float y = UV.y;
    
    // Snap vertical baseado no canal_width (em pixels) para alinhar à grade pixel art
    float y_px = y * canal_width;
    float y_snapped_px = floor(y_px / pixel_size) * pixel_size;
    float y_snapped = y_snapped_px / canal_width;
    
    // Posição x em pixels ao longo do canal
    float pos_x = UV.x * canal_length;
    
    if (y_snapped < 0.12) {
        // Calçada Superior
        float t = y_snapped / 0.12;
        vec4 col = mix(vec4(0.60, 0.60, 0.60, 1.0), vec4(0.50, 0.50, 0.50, 1.0), t); // Cinza calçada
        
        // Detalhes/Rachaduras usando hash
        vec2 snap_pos = floor(world_pos / pixel_size) * pixel_size;
        if (hash2d(snap_pos) > 0.94) {
            col.rgb *= 0.75;
        }
        COLOR = col;
    }
    else if (y_snapped > 0.88) {
        // Calçada Inferior
        float t = (1.0 - y_snapped) / 0.12;
        vec4 col = mix(vec4(0.55, 0.55, 0.55, 1.0), vec4(0.45, 0.45, 0.45, 1.0), t);
        
        vec2 snap_pos = floor(world_pos / pixel_size) * pixel_size;
        if (hash2d(snap_pos) > 0.94) {
            col.rgb *= 0.75;
        }
        COLOR = col;
    }
    else if (y_snapped < 0.28) {
        // Parede Superior
        float t = (y_snapped - 0.12) / 0.16;
        vec4 col = mix(vec4(0.35, 0.35, 0.35, 1.0), vec4(0.22, 0.22, 0.22, 1.0), t); // Concreto escuro
        
        vec2 snap_pos = floor(world_pos / pixel_size) * pixel_size;
        if (hash2d(snap_pos) > 0.94) {
            col.rgb *= 0.75;
        }
        COLOR = col;
    }
    else if (y_snapped > 0.72) {
        // Parede Inferior
        float t = (0.88 - y_snapped) / 0.16;
        vec4 col = mix(vec4(0.32, 0.32, 0.32, 1.0), vec4(0.20, 0.20, 0.20, 1.0), t);
        
        vec2 snap_pos = floor(world_pos / pixel_size) * pixel_size;
        if (hash2d(snap_pos) > 0.94) {
            col.rgb *= 0.75;
        }
        COLOR = col;
    }
    else {
        // ── Água do Canal com Fluxo Longitudinal e Brilho Shimmer ──────────────
        // Normaliza y da água (dentro dos limites 0.28 e 0.72)
        float water_y = (y_snapped - 0.28) / 0.44;
        
        // Posição local do canal em pixels (alinha fluxo ao longo do canal curvo)
        vec2 canal_pos = vec2(pos_x, water_y * canal_width * 2.0);
        
        // Direções de fluxo para as camadas de ruído (longitudinal em X)
        vec2 dir1 = normalize(direction);
        vec2 dir2 = vec2(-dir1.y, dir1.x);
        
        vec2 offset1 = dir1 * (TIME * flow_speed * 15.0);
        vec2 offset2 = dir2 * (TIME * flow_speed * 11.0);
        
        // Snapping das posições do canal para manter o pixel perfect e evitar jitter
        vec2 snapped_canal_pos1 = floor((canal_pos + offset1) / pixel_size) * pixel_size;
        vec2 snapped_canal_pos2 = floor((canal_pos + offset2) / pixel_size) * pixel_size;
        
        vec2 noise_uv1 = snapped_canal_pos1 * noise_scale;
        vec2 noise_uv2 = snapped_canal_pos2 * noise_scale;
        
        // Leitura do ruído
        float n1 = texture(noise_texture, noise_uv1).r;
        float n2 = texture(noise_texture, noise_uv2).r;
        
        float combined_noise = (n1 + n2) * 0.5;
        
        // Distorção das coordenadas para ondas e fluxo orgânico
        vec2 distortion = vec2(n1 - 0.5, n2 - 0.5) * wave_strength;
        vec2 snapped_distortion = floor(distortion / pixel_size) * pixel_size;
        
        vec2 dist_canal_pos = canal_pos + snapped_distortion;
        
        // Amostragem da textura de água base nas posições distorcidas e movidas
        vec2 base_uv1 = (dist_canal_pos + offset1 * 0.2) * wave_scale;
        vec2 base_uv2 = (dist_canal_pos + offset2 * 0.2) * wave_scale;
        
        vec4 tex1 = texture(TEXTURE, base_uv1);
        vec4 tex2 = texture(TEXTURE, base_uv2);
        
        // Otimização de performance branchless
        float m = step(tex1.r, tex2.r);
        vec4 base_color = mix(tex1, tex2, m);
        
        // Gradiente de profundidade: escuro no centro, claro nas bordas
        float depth = abs(water_y - 0.5) * 2.0; // 0.0 no centro, 1.0 nas margens
        vec4 water_color = mix(deep_color, shallow_color, depth);
        
        // Mesclar cor de profundidade com a textura base pixelada
        water_color = mix(water_color, base_color, 0.6);
        
        // Brilho estático suave nas margens da mureta
        float border_glow = smoothstep(0.70, 1.0, depth);
        water_color = mix(water_color, glow_color, border_glow * 0.30);
        
        // Aplicar o shimmer (brilho) dinâmico
        float shimmer_threshold = 1.0 - detail;
        float shimmer = smoothstep(shimmer_threshold, shimmer_threshold + 0.1, combined_noise);
        
        water_color.rgb = mix(water_color.rgb, shimmer_color.rgb * brightness, shimmer * opacity);
        
        COLOR = water_color;
    }
}
