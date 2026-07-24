shader_type canvas_item;

uniform vec4 team_color : source_color = vec4(0.31, 0.64, 1.0, 1.0);

void fragment() {
    vec4 source = texture(TEXTURE, UV);
    float blue_dominance = source.b - max(source.r, source.g);
    float blue_mask = smoothstep(0.045, 0.30, blue_dominance) * smoothstep(0.12, 0.42, source.b);
    float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
    vec3 replacement = team_color.rgb * (0.40 + luminance * 0.95);
    vec3 color = mix(source.rgb, replacement, blue_mask * 0.92);
    COLOR = vec4(color, source.a * team_color.a);
}
