shader_type canvas_item;

// Parâmetros de cor
uniform vec4 shallow_color : hint_color = vec4(0.18, 0.48, 0.76, 1.0); // Azul claro nas bordas
uniform vec4 deep_color    : hint_color = vec4(0.12, 0.36, 0.64, 1.0); // Azul escuro no centro
uniform vec4 glow_color    : hint_color = vec4(0.50, 0.75, 0.95, 1.0); // Espuma/Glow nas margens
uniform vec4 wave_color    : hint_color = vec4(0.15, 0.42, 0.70, 1.0); // Onda estática intermediária

uniform float canal_length = 100.0;  // Comprimento em pixels
uniform float canal_width = 24.0;    // Largura em pixels (espessura da linha)
uniform float pixel_size = 2.0;      // Tamanho do pixel virtual (escala 2x)

varying vec2 world_pos;

void vertex() {
    world_pos = VERTEX;
}

// Função de hash pseudo-aleatória para manchas do concreto
float hash2d(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Ruído suave interpolado (Value Noise) para ondas estáticas
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash2d(i);
    float b = hash2d(i + vec2(1.0, 0.0));
    float c = hash2d(i + vec2(0.0, 1.0));
    float d = hash2d(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
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
        // ── Água Estática no Centro (Sem Movimento) ───────────────────────────
        // Normaliza y da água (dentro dos limites 0.28 e 0.72)
        float water_y = (y_snapped - 0.28) / 0.44;
        
        // Gradiente de profundidade: escuro no centro, claro nas bordas
        float depth = abs(water_y - 0.5) * 2.0; // 0.0 no centro, 1.0 nas margens
        vec4 water_color = mix(deep_color, shallow_color, depth);
        
        // Brilho estático nas margens (onde a água encosta na mureta)
        float border_glow = smoothstep(0.70, 1.0, depth);
        water_color = mix(water_color, glow_color, border_glow * 0.40);
        
        // Ondas estáticas desenhadas proceduralmente e snappadas ao grid pixel art
        vec2 noise_pos = vec2(
            floor(pos_x / pixel_size) * pixel_size * 0.08,
            floor(water_y * 12.0)
        );
        
        float n = value_noise(noise_pos);
        
        // Detalhes e espuma estática
        if (n > 0.72) {
            water_color = mix(water_color, glow_color, 0.65);
        } else if (n > 0.58) {
            water_color = mix(water_color, wave_color, 0.50);
        }
        
        COLOR = water_color;
    }
}
