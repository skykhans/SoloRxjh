shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_deep : source_color = vec4(0.18, 0.29, 0.17, 1.0);
uniform vec4 grass_light : source_color = vec4(0.34, 0.43, 0.23, 1.0);
uniform vec4 moss_color : source_color = vec4(0.30, 0.40, 0.22, 1.0);
uniform vec4 earth_color : source_color = vec4(0.38, 0.34, 0.25, 1.0);

varying vec3 world_position;


float hash_cell(vec2 cell) {
	vec3 seed = vec3(cell.x, cell.y, cell.x);
	return fract(sin(dot(seed, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float lower = mix(
		hash_cell(cell),
		hash_cell(cell + vec2(1.0, 0.0)),
		local.x
	);
	float upper = mix(
		hash_cell(cell + vec2(0.0, 1.0)),
		hash_cell(cell + vec2(1.0, 1.0)),
		local.x
	);
	return mix(lower, upper, local.y);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 field = world_position.xz;
	float broad = value_noise(field * 0.22);
	float detail = value_noise(field * 1.7);
	float flecks = value_noise(field * 5.2);
	float turf = broad * 0.58 + detail * 0.30 + flecks * 0.12;
	vec3 grass = mix(grass_deep.rgb, grass_light.rgb, smoothstep(0.24, 0.78, turf));
	float moss = smoothstep(0.69, 0.83, broad + detail * 0.12);
	grass = mix(grass, moss_color.rgb, moss * 0.38);

	float path_curve = 0.18 * sin(field.y * 0.17);
	float path_distance = abs(field.x - path_curve);
	float path_edge = 1.0 - smoothstep(1.35, 2.65, path_distance);
	float path_texture = value_noise(field * 0.72);
	vec3 earth = mix(earth_color.rgb * 0.82, earth_color.rgb * 1.12, path_texture);

	ALBEDO = mix(grass, earth, path_edge * 0.86);
	ROUGHNESS = 0.96;
}
