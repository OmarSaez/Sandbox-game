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

        // CANNON SPECIAL RENDERING (IDs: 95, 195, 295, 395, 495, 595, 695, 795)
        if (id == 95 || id == 195 || id == 295 || id == 395 || id == 495 || id == 595 || id == 695 || id == 795) {
            int orient = (id - 95) / 100;

            // Decode px and py from Alpha variant (Byte 3)
            int px = variant & 0x0F;
            int py = variant >> 4;

            bool is_base = false;
            bool is_body = (px >= 4 && px <= 7 && py >= 4 && py <= 7);
            bool is_pivot = false;
            bool is_barrel = false;

            if (orient == 0) {
                if (px == 8 && (py == 5 || py == 6)) {
                    is_pivot = true;
                } else if (px == 9 && (py == 5 || py == 6)) {
                    is_barrel = true;
                }
            } else if (orient == 1) {
                if ((px == 7 && py == 3) || (px == 8 && py == 4)) {
                    is_pivot = true;
                } else if ((px == 8 && (py == 2 || py == 3)) || (px == 9 && py == 3)) {
                    is_barrel = true;
                }
            } else if (orient == 2) {
                if ((px == 5 || px == 6) && py == 3) {
                    is_pivot = true;
                } else if ((px == 5 || px == 6) && (py == 1 || py == 2)) {
                    is_barrel = true;
                }
            } else if (orient == 3) {
                if ((px == 4 && py == 3) || (px == 3 && py == 4)) {
                    is_pivot = true;
                } else if ((px == 3 && (py == 2 || py == 3)) || (px == 2 && py == 3)) {
                    is_barrel = true;
                }
            } else if (orient == 4) {
                if (px == 3 && (py == 5 || py == 6)) {
                    is_pivot = true;
                } else if (px == 2 && (py == 5 || py == 6)) {
                    is_barrel = true;
                }
            } else if (orient == 5) {
                if ((px == 4 && py == 8) || (px == 3 && py == 7)) {
                    is_pivot = true;
                } else if ((px == 3 && (py == 9 || py == 8)) || (px == 2 && py == 8)) {
                    is_barrel = true;
                }
            } else if (orient == 6) {
                if ((px == 5 || px == 6) && py == 8) {
                    is_pivot = true;
                } else if ((px == 5 || px == 6) && (py == 10 || py == 9)) {
                    is_barrel = true;
                }
            } else if (orient == 7) {
                if ((px == 7 && py == 8) || (px == 8 && py == 7)) {
                    is_pivot = true;
                } else if ((px == 8 && (py == 9 || py == 8)) || (px == 9 && py == 8)) {
                    is_barrel = true;
                }
            }

            if (!is_body && !is_pivot && !is_barrel) {
                is_base = true;
            }

            // Apply Palette & Custom Colors
            if (is_base) {
                color.rgb = vec3(0.96, 0.96, 0.98); // Creamy white
            } else if (is_pivot) {
                color.rgb = vec3(0.96, 0.1, 0.1); // Bright red
            } else if (is_body) {
                // Steel-blue body with outer outlines and active core
                if (px >= 5 && px <= 6 && py >= 5 && py <= 6) {
                    if (charge > 0.05) {
                        color.rgb = vec3(1.0, 0.7, 0.1); // Glow yellow-orange when active
                    } else {
                        color.rgb = vec3(0.7, 0.2, 0.05); // Inactive ember core
                    }
                } else if (px == 4 || px == 7 || py == 4 || py == 7) {
                    color.rgb = vec3(0.22, 0.28, 0.35); // Dark steel metallic frame
                } else {
                    color.rgb = vec3(0.35, 0.46, 0.57); // Steel blue
                }
            } else if (is_barrel) {
                bool is_tip = false;
                if (orient == 0 && px == 9) is_tip = true;
                else if (orient == 1 && px == 9 && py == 2) is_tip = true;
                else if (orient == 2 && py == 1) is_tip = true;
                else if (orient == 3 && px == 2 && py == 2) is_tip = true;
                else if (orient == 4 && px == 2) is_tip = true;
                else if (orient == 5 && px == 2 && py == 9) is_tip = true;
                else if (orient == 6 && py == 10) is_tip = true;
                else if (orient == 7 && px == 9 && py == 9) is_tip = true;

                if (is_tip) {
                    color.rgb = vec3(0.18, 0.22, 0.28); // Dark muzzle opening
                } else {
                    color.rgb = vec3(0.35, 0.46, 0.57); // Steel blue barrel body
                }
            } else {
                color.rgb = vec3(0.35, 0.46, 0.57); // Safe fallback
            }
        }
        
        // Dimmed inactive LED color override based on variant
        if (id == 89) {
            int color_idx = variant & 7;
            vec3 inactive_color = vec3(0.33, 0.07, 0.07); // Default Dark Red
            if (color_idx == 1) inactive_color = vec3(0.07, 0.15, 0.33); // Dark Blue
            else if (color_idx == 2) inactive_color = vec3(0.07, 0.33, 0.07); // Dark Green
            else if (color_idx == 3) inactive_color = vec3(0.33, 0.28, 0.05); // Dark Yellow
            else if (color_idx == 4) inactive_color = vec3(0.35, 0.35, 0.35); // Dark White
            else if (color_idx == 5) inactive_color = vec3(0.33, 0.07, 0.25); // Dark Pink
            else if (color_idx == 6) inactive_color = vec3(0.05, 0.25, 0.33); // Dark Sky Blue
            color.rgb = inactive_color;
        }


        // EXPLOSIVE PRE-FLASH
        if (charge > 0.05 && (id == 5 || id == 7 || id == 18 || id == 19 || id == 20 || id == 71 || id == 72 || id == 77)) {
            // Flash pure white depending on charge intensity
            color = mix(color, vec4(1.0, 1.0, 1.0, 1.0), charge);
        }

        // 5. ELECTRIC GLOW (High Intensity Sparks with Amber Contrast)
        if (charge > 0.05 && id > 0 && id != 13 && id != 25 && id != 5 && id != 7 && id != 18 && id != 19 && id != 20 && id != 71 && id != 72 && id != 77 && id != 90 && id != 91 && id != 95 && id != 195 && id != 295 && id != 395 && id != 495 && id != 595 && id != 695 && id != 795 && id != 96) {
            float spark_intensity = smoothstep(0.12, 1.0, charge);
            vec4 electric_color = vec4(1.0, 0.7, 0.0, 1.0); // Amber/Orange-Yellow default
            
            if (id == 89) {
                int color_idx = variant & 7;
                vec4 led_color = vec4(1.0, 0.1, 0.1, 1.0); // Default Red
                vec3 glow_color = vec3(0.8, 0.0, 0.0);
                
                if (color_idx == 1) { // Blue
                    led_color = vec4(0.15, 0.45, 1.0, 1.0);
                    glow_color = vec3(0.0, 0.3, 0.8);
                } else if (color_idx == 2) { // Green
                    led_color = vec4(0.15, 1.0, 0.15, 1.0);
                    glow_color = vec3(0.0, 0.8, 0.0);
                } else if (color_idx == 3) { // Yellow
                    led_color = vec4(1.0, 0.85, 0.05, 1.0);
                    glow_color = vec3(0.8, 0.65, 0.0);
                } else if (color_idx == 4) { // White
                    led_color = vec4(1.0, 1.0, 1.0, 1.0);
                    glow_color = vec3(0.7, 0.7, 0.7);
                } else if (color_idx == 5) { // Pink
                    led_color = vec4(1.0, 0.25, 0.75, 1.0);
                    glow_color = vec3(0.8, 0.0, 0.55);
                } else if (color_idx == 6) { // Sky Blue / Celeste
                    led_color = vec4(0.2, 0.8, 1.0, 1.0);
                    glow_color = vec3(0.0, 0.55, 0.8);
                }
                
                color.rgb = mix(color.rgb, color.rgb * 0.3, spark_intensity * 0.5);
                color = mix(color, led_color, spark_intensity * 0.95);
                color.rgb += glow_color * (charge * 2.5);
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
