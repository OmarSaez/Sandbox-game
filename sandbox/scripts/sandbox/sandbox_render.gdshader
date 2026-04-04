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
    // Material IDs (0-65535) use R and G bytes, and variant uses A.
    // Blue channel (B) is reserved as a marker for visual effects (Sparks/Rockets).
    if (raw_data.b > 0.005) {
        COLOR = raw_data;
    } else {
        // 3. MATERIAL ID RENDERING
        int id_low = int(raw_data.r * 255.0 + 0.5);
        int id_high = int(raw_data.g * 255.0 + 0.5);
        int id = id_low + (id_high * 256);
        
        // Scalable Texturing: Get Variant from Alpha channel (Byte 3)
        int variant = int(raw_data.a * 255.0 + 0.5);
        float py = (float(variant) + 0.5) / 3.0; // 3 rows for variants
        
        // Get Charge from secondary L8 texture
        float charge = texture(charge_tex, UV).r;
        
        // Palette Lookup with variant row offset (Now 2048 wide)
        vec4 color = texture(palette_tex, vec2((float(id) + 0.5) / 2048.0, py));
        
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
        
        // 5. ELECTRIC GLOW (High Intensity Sparks with Amber Contrast)
        if (charge > 0.05 && id > 0 && id != 13 && id != 25 && id != 5 && id != 7 && id != 20 && id != 71 && id != 72 && id != 77) {
            float spark_intensity = smoothstep(0.12, 1.0, charge);
            vec4 electric_amber = vec4(1.0, 0.7, 0.0, 1.0); // Amber/Orange-Yellow for better contrast on white
            
            // Darken the background slightly under the spark to make it pop on white metal
            color.rgb = mix(color.rgb, color.rgb * 0.5, spark_intensity * 0.7);
            
            // Brighter Amber Core
            color = mix(color, electric_amber, spark_intensity * 0.9);
            color.rgb += vec3(0.6, 0.3, 0.0) * (charge * 2.0); // Hot core glow
        }
        
        COLOR = color;
    }
}
