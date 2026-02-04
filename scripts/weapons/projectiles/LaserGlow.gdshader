shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float pulse_speed = 6.0;
uniform float pulse_strength = 0.35;
uniform float glow_boost = 1.2;

void fragment() {
	vec4 c = COLOR;
	float pulse = 1.0 + pulse_strength * sin(TIME * pulse_speed);
	c.rgb *= glow_boost * pulse;
	c.a *= pulse;
	COLOR = c;
}
