shader_type canvas_item;

uniform sampler2D id_tex; // R=ID, G=Charge, B=0, A=255
uniform sampler2D palette_tex : filter_nearest; // 256x1 Palette
uniform float tornado_x;
uniform float tornado_ground_y;
uniform float tornado_intensity;

void fragment() {
    // 1. Get raw material ID and Charge from our packed RGBA texture
    vec4 data = texture(id_tex, UV);
    float id_raw = data.r;
    float charge_raw = data.g; 
    
    // Map ID float (0.0-1.0) back to 0-255 integer safely
    int id = int(id_raw * 255.0 + 0.1);
    
    // 2. Lookup material color from the palette
    // Always sample the center of the pixel: (index + 0.5) / 256.0
    float u = (float(id) + 0.5) / 256.0;
    vec4 color = texture(palette_tex, vec2(u, 0.5));
    
    // 3. Simple Electric Glow for conductors (Logic from GDScript original)
    // ID 13 is Acid, we exclude its glow to keep it green.
    // Conductors usually have charge > 80 (approx 0.31 normalized)
    if (charge_raw > 0.31 && id != 13 && id > 0) {
        float glow = (charge_raw - 0.31) / 0.69;
        color = mix(color, vec4(1.0, 1.0, 0.0, 1.0), glow * 0.4); 
    }
    
    // 4. Ghost Tornado Visual (drawn on empty space ID 0)
    if (tornado_intensity > 0.0 && id == 0) {
        vec2 tex_size = vec2(textureSize(id_tex, 0));
        vec2 grid_pos = UV * tex_size;
        
        if (grid_pos.y <= tornado_ground_y) {
            float rel_y = 1.0 - (grid_pos.y / tornado_ground_y);
            float cur_rad = (5.0 + tornado_intensity * 5.0) + (40.0 * tornado_intensity * rel_y);
            if (abs(grid_pos.x - tornado_x) < cur_rad) {
                color = vec4(0.4, 0.4, 0.4, 0.3);
            }
        }
    }
    
    COLOR = color;
}
