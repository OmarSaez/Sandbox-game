shader_type canvas_item;

uniform sampler2D palette_tex : filter_nearest;
uniform sampler2D charge_tex : filter_nearest;
uniform sampler2D background_tex : filter_nearest;
uniform sampler2D element_color_tex : filter_nearest;

uniform float tornado_x = -100.0;
uniform float tornado_ground_y = 1000.0;
uniform float tornado_intensity = 0.0;

int get_mat_id(sampler2D tex, vec2 uv, vec2 offset, vec2 tex_size) {
    vec4 raw = texture(tex, uv + offset / tex_size);
    int low = int(raw.r * 255.0 + 0.5);
    int high = int(raw.g * 255.0 + 0.5);
    return low + (high * 256);
}

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
        
        // 4. BACKGROUND PAINTING (Apply background_tex if cell is air/ID 0)
        if (id == 0) {
            color = texture(background_tex, UV);
        } else {
            // ELEMENT COLOR OVERLAY (Paint over existing materials)
            vec4 overlay = texture(element_color_tex, UV);
            if (overlay.a > 0.01) {
                color.rgb = overlay.rgb;
            }
        }
        
        // LOGIC GATE CUSTOM PIN FEEDBACK (Outer 2 pixels border for Inputs/Outputs)
        if (id >= 81 && id <= 87 && variant >= 10 && variant <= 17) {
            ivec2 tex_size = textureSize(TEXTURE, 0);
            ivec2 coord = ivec2(UV * vec2(tex_size));
            int px = coord.x % 4;
            int py = coord.y % 4;
            
            bool is_edge = false;
            if (variant == 10 || variant == 14) is_edge = (py < 2);
            else if (variant == 11 || variant == 15) is_edge = (px >= 2);
            else if (variant == 12 || variant == 16) is_edge = (py >= 2);
            else if (variant == 13 || variant == 17) is_edge = (px < 2);
            
            if (is_edge) {
                bool is_output = (variant >= 14);
                if (is_output) {
                    if (charge > 0.05) {
                        color = vec4(0.25, 1.0, 1.0, 1.0); // #40FFFF (Active Output)
                    } else {
                        color = vec4(0.61, 0.73, 0.73, 1.0); // #9CBABA (Inactive Output)
                    }
                } else {
                    if (charge > 0.05) {
                        color = vec4(0.77, 0.67, 0.67, 1.0); // #C4ABAB (Active Input)
                    } else {
                        color = vec4(0.49, 0.49, 0.49, 1.0); // #7D7D7D (Inactive Input)
                    }
                }
            }
        }
        

        // NPC ACTIVATOR (ID 90) CUSTOM FEEDBACK
        if (id == 90) {
            ivec2 tex_size = textureSize(TEXTURE, 0);
            ivec2 coord = ivec2(UV * vec2(tex_size));
            int px = coord.x % 4;
            int py = coord.y % 4;
            if (charge > 0.05) {
                // Glow bright pink/violet (#E0A8FF)
                color.rgb = vec3(0.88, 0.66, 1.0);
            } else {
                // Dark purple (#6A20A0)
                color.rgb = vec3(0.42, 0.13, 0.63);
            }
            // Draw a subtle border around the pressure plate
            if (px == 0 || px == 3 || py == 0 || py == 3) {
                color.rgb *= 0.5;
            }
        }
        
        // NPC DOOR (ID 91) CUSTOM FEEDBACK
        if (id == 91) {
            ivec2 tex_size = textureSize(TEXTURE, 0);
            ivec2 coord = ivec2(UV * vec2(tex_size));
            int px = coord.x % 4;
            int py = coord.y % 4;
            if (charge > 0.05) {
                // Blend with background to look open / passable
                vec4 bg_color = texture(background_tex, UV);
                color.rgb = mix(vec3(0.7, 1.0, 0.7), bg_color.rgb, 0.85); // 85% background, 15% green glow
                // Draw a nice dashed green frame to show it is active/open
                if (px == 0 || px == 3 || py == 0 || py == 3) {
                    color.rgb = mix(color.rgb, vec3(0.2, 1.0, 0.2), 0.5);
                }
            } else {
                // Closed state: solid wood color from palette, with a dark wooden panel frame
                if (px == 0 || px == 3 || py == 0 || py == 3) {
                    color.rgb *= 0.55; // Wooden outline
                }
            }
        }

        // CANNON (ID 95) SPECIAL RENDERING
        if (id == 95) {
            ivec2 tex_size = textureSize(TEXTURE, 0);
            ivec2 coord = ivec2(UV * vec2(tex_size));
            int px = coord.x % 4;
            int py = coord.y % 4;
            
            // Outer frame
            if (px == 0 || px == 3 || py == 0 || py == 3) {
                color.rgb *= 0.6; // Dark metallic frame
            }
            
            // Draw barrel depending on variant (1: UP, 2: RIGHT, 3: DOWN, 4: LEFT)
            if (variant == 1) { // UP
                if ((px == 1 || px == 2) && (py == 0 || py == 1)) {
                    color.rgb = vec3(0.08, 0.09, 0.12); // Hollow dark barrel
                }
            } else if (variant == 2) { // RIGHT
                if ((px == 2 || px == 3) && (py == 1 || py == 2)) {
                    color.rgb = vec3(0.08, 0.09, 0.12);
                }
            } else if (variant == 3) { // DOWN
                if ((px == 1 || px == 2) && (py == 2 || py == 3)) {
                    color.rgb = vec3(0.08, 0.09, 0.12);
                }
            } else if (variant == 4) { // LEFT
                if ((px == 0 || px == 1) && (py == 1 || py == 2)) {
                    color.rgb = vec3(0.08, 0.09, 0.12);
                }
            }
            
            // Center glowing core (grows brighter with charge)
            if (px >= 1 && px <= 2 && py >= 1 && py <= 2 && !(variant == 1 && py == 1) && !(variant == 2 && px == 2) && !(variant == 3 && py == 2) && !(variant == 4 && px == 1)) {
                vec3 glow_color = vec3(0.9, 0.25, 0.05); // Energetic amber-orange
                if (charge > 0.05) {
                    glow_color = vec3(1.0, 0.6, 0.0); // Bright charged yellow-orange
                }
                color.rgb = mix(color.rgb, glow_color, 0.7);
            }
        }


        // 5. ELECTRIC GLOW (High Intensity Sparks with Amber Contrast)
        if (charge > 0.05 && id > 0 && id != 13 && id != 25 && id != 5 && id != 7 && id != 20 && id != 71 && id != 72 && id != 77 && id != 90 && id != 91 && id != 95 && id != 96) {
            float spark_intensity = smoothstep(0.12, 1.0, charge);
            vec4 electric_color = vec4(1.0, 0.7, 0.0, 1.0); // Amber/Orange-Yellow default
            
            if (id == 89) {
                // LED glows bright crimson red with high bloom core
                electric_color = vec4(1.0, 0.1, 0.1, 1.0);
                color.rgb = mix(color.rgb, color.rgb * 0.3, spark_intensity * 0.5);
                color = mix(color, electric_color, spark_intensity * 0.95);
                color.rgb += vec3(0.8, 0.0, 0.0) * (charge * 2.5); // Rich red core glow
            } else {
                // Darken the background slightly under the spark to make it pop on white metal
                color.rgb = mix(color.rgb, color.rgb * 0.5, spark_intensity * 0.7);
                
                // Brighter Amber Core
                color = mix(color, electric_color, spark_intensity * 0.9);
                color.rgb += vec3(0.6, 0.3, 0.0) * (charge * 2.0); // Hot core glow
            }
        }
        
        COLOR = color;
    }
}
