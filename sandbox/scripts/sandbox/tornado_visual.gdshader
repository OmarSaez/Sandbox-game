shader_type canvas_item;

uniform float intensity = 1.0;
uniform float ground_y = 600.0;
uniform vec3 dust_color = vec3(0.35, 0.33, 0.3);

void fragment() {
    vec2 pos = UV; // 0 to 1
    
    // Inverted Triangle Mask
    // At y=0 (top), width is full (0 to 1)
    // At y=1 (bottom), width is small (0.45 to 0.55)
    float funnel_width = mix(0.1, 1.0, 1.0 - pos.y);
    float dist_from_center = abs(pos.x - 0.5) * 2.0;
    
    if (dist_from_center > funnel_width) {
        discard;
    }
    
    // Swirling Noise Logic
    float angle = (pos.x - 0.5) / (funnel_width * 0.5);
    float swirl = sin(angle * 4.0 + TIME * 25.0 + pos.y * 10.0);
    float vertical = sin(pos.y * 15.0 - TIME * 30.0);
    
    // Alpha density
    float alpha = (1.0 - dist_from_center) * 0.7 * (intensity / 3.0);
    alpha *= (0.6 + 0.4 * swirl + 0.1 * vertical);
    
    // Fade at the very top and bottom
    alpha *= smoothstep(1.0, 0.8, pos.y); // Bottom fade
    alpha *= smoothstep(0.0, 0.2, pos.y); // Top fade
    
    COLOR = vec4(dust_color, clamp(alpha, 0.0, 0.8));
    
    // Add a slightly darker core
    float core = smoothstep(0.4, 0.0, dist_from_center);
    COLOR.rgb *= mix(1.0, 0.7, core);
    COLOR.a = clamp(COLOR.a + core * 0.2 * (intensity/3.0), 0.0, 0.9);
}
