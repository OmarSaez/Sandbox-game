shader_type canvas_item;

uniform sampler2D palette_tex : filter_nearest;
uniform sampler2D charge_tex : filter_nearest;

uniform float tornado_x = -100.0;
uniform float tornado_ground_y = 1000.0;
uniform float tornado_intensity = 0.0;

void fragment() {
    // 1. Get raw pixel data (R = ID, G = Direct Color Marker)
    vec4 raw_data = texture(TEXTURE, UV);
    
    // 2. HYBRID RENDERING DETECTION
    // If Green or Blue channels have data, it's a visual effect (Spark/Rocket) 
    if (raw_data.g > 0.01 || raw_data.b > 0.01) {
        COLOR = raw_data;
    } else {
        // 3. MATERIAL ID RENDERING
        int id = int(raw_data.r * 255.0 + 0.1);
        
        // Get Charge from secondary L8 texture
        float charge = texture(charge_tex, UV).r;
        
        // Palette Lookup
        vec4 color = texture(palette_tex, vec2((float(id) + 0.5) / 256.0, 0.5));
        
        // 4. Tornado Funnel for Air (ID 0)
        if (id == 0 && tornado_intensity > 0.0) {
            vec2 tex_size = vec2(textureSize(TEXTURE, 0));
            vec2 grid_pos = UV * tex_size;
            if (grid_pos.y <= tornado_ground_y) {
                float rel_y = 1.0 - (grid_pos.y / tornado_ground_y);
                float cur_rad = (5.0 + tornado_intensity * 5.0) + (40.0 * tornado_intensity * rel_y);
                if (abs(grid_pos.x - tornado_x) < cur_rad) {
                    color = vec4(0.4, 0.4, 0.4, 0.4);
                }
            }
        }
        
        // 5. ELECTRIC GLOW (Exclude Fresh Cement ID 25 and Acid ID 13)
        // Only glow if charge is high (> 0.1) and it's NOT a material using charge for metadata
        if (charge > 0.1 && id > 0 && id != 13 && id != 25) {
            vec4 electric_yellow = vec4(1.0, 1.0, 0.0, 1.0);
            color = mix(color, electric_yellow, 0.9);
            color.rgb += vec3(0.2, 0.2, 0.0);
        }
        
        COLOR = color;
    }
}
