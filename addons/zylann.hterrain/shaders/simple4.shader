shader_type spatial;

uniform sampler2D height_texture;
uniform sampler2D normal_texture;
uniform sampler2D color_texture : hint_albedo;
uniform sampler2D splat_texture;
uniform sampler2D mask_texture;
uniform vec2 heightmap_resolution;
uniform mat4 heightmap_inverse_transform;

uniform sampler2D detail_albedo_0 : hint_albedo;
uniform sampler2D detail_albedo_1 : hint_albedo;
uniform sampler2D detail_albedo_2 : hint_albedo;
uniform sampler2D detail_albedo_3 : hint_albedo;
uniform sampler2D detail_albedo_4 : hint_albedo;
uniform float detail_scale = 20.0;

vec3 unpack_normal(vec3 rgb) {
	return rgb * 2.0 - vec3(1.0);
}

void vertex() {
	vec4 tv = heightmap_inverse_transform * WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 uv = vec2(tv.x, tv.z) / heightmap_resolution;
	float h = texture(height_texture, uv).r;
	VERTEX.y = h;
	UV = uv;
	NORMAL = unpack_normal(texture(normal_texture, UV).rgb);
}

void fragment() {

	float mask = texture(mask_texture, UV).r;
	if(mask < 0.5)
		discard;

	vec3 n = unpack_normal(texture(normal_texture, UV).rgb);
	NORMAL = (INV_CAMERA_MATRIX * (WORLD_MATRIX * vec4(n, 0.0))).xyz;
	
	vec4 splat = texture(splat_texture, UV);

	// TODO Detail should only be rasterized on nearby chunks (needs proximity management to switch shaders)
	
	// TODO Should use local XZ
	vec2 detail_uv = UV * detail_scale;
	vec4 col0 = texture(detail_albedo_0, detail_uv);
	vec4 col1 = texture(detail_albedo_1, detail_uv);
	vec4 col2 = texture(detail_albedo_2, detail_uv);
	vec4 col3 = texture(detail_albedo_3, detail_uv);
	vec4 col4 = texture(detail_albedo_4, detail_uv);
	
	vec3 tint = texture(color_texture, UV).rgb;
	
	float base_amount = 1.0 - (splat.r + splat.g + splat.b + splat.a);
	
	/*float s = 0.1;
	float h0 = col0.r * base_amount;
	float h1 = col1.r * col0.r;
	float w0 = smoothstep(h1, h1+s, h0);
	float w1 = smoothstep(h0-s, h0, h1);
	vec3 hc = w0 * col0.rgb + w1 * col1.rgb;*/
	
	ALBEDO = (base_amount * col0.rgb + (col1.rgb * splat.r + col2.rgb * splat.g + col3.rgb * splat.b + col4.rgb * splat.a));
}

