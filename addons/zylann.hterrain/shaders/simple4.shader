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

uniform bool depth_blending = true;


vec3 unpack_normal(vec3 rgb) {
	return rgb * 2.0 - vec3(1.0);
}

float brightness(vec3 rgb) {
	// TODO Hey dude, you lazy
	return 0.33 * (rgb.r + rgb.g + rgb.b);
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
	
	float w0, w1, w2, w3, w4;
	
	// TODO An #ifdef macro would be nice!
	if (depth_blending) {
	
		float h0 = brightness(col0.rgb) * base_amount;// - 0.8;
	    float h1 = brightness(col1.rgb) * splat.r;
	    float h2 = brightness(col2.rgb) * splat.g;
	    float h3 = brightness(col3.rgb) * splat.b;
	    float h4 = brightness(col4.rgb) * splat.a;
	
		// Doesn't look great with more than 2 textures,
		// so had to nullify this parameter for now...
		// TODO Improve multi-texture depth blending
	    float d = 0.001;
	
		float ma = max(h0, max(max(h1, h2), max(h3, h4))) - d;
		
		w0 = max(h0 - ma, 0.0);
		w1 = max(h1 - ma, 0.0);
		w2 = max(h2 - ma, 0.0);
		w3 = max(h3 - ma, 0.0);
		w4 = max(h4 - ma, 0.0);
		
	} else {
		
		w0 = base_amount;
		w1 = splat.r;
		w2 = splat.g;
		w3 = splat.b;
		w4 = splat.a;
	}
	
    vec3 hc = (w0 * col0.rgb + w1 * col1.rgb + w2 * col2.rgb + w3 * col3.rgb + w4 * col4.rgb) / (w0 + w1 + w2 + w3 + w4); 
	
	ALBEDO = hc;
}

