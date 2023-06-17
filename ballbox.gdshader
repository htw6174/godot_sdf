shader_type spatial;
render_mode cull_back;

// too large will expand shapes, but too small will be more expensive and may reveal 'misses'
#define MIN 0.00015
// too large will be more expensive, too small will limit ray penetraion into volume
#define MAX 100.0

uniform vec3 color : source_color;
uniform int steps = 256;
uniform bool set_depth = true;
uniform vec3 box = vec3(0.5, 0.5, 1.0);
//uniform mat4 inverse_model; // TODO: probably better to provide this, instead of computing per fragment

// Credit for sdf utility functions goes to iq https://iquilezles.org/articles/distfunctions/
float sdSphere(in vec3 p, float r) {
	return length(p) - r;
}

float sdBox(in vec3 p, in vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float map(in vec3 pos, in mat4 invmodel) {
	pos = (invmodel * vec4(pos, 1.0)).xyz; // apply model to world space transform
	float d = -sdBox(pos, box);
	float moverange = (box.z * 0.5) - 0.5;
	pos.z += sin(TIME * 4.0) * moverange + (box.z * 0.5);
	d = min(d, sdSphere(pos, 0.3));
	return d;
}

// https://iquilezles.org/articles/normalsSDF
vec3 calcNormal(in vec3 pos, in mat4 invmodel)
{
    vec2 e = vec2(1.0,-1.0)*0.5773;
    const float eps = 0.0005;
    return normalize( e.xyy*map(pos + e.xyy*eps, invmodel) + 
					  e.yyx*map(pos + e.yyx*eps, invmodel) + 
					  e.yxy*map(pos + e.yxy*eps, invmodel) + 
					  e.xxx*map(pos + e.xxx*eps, invmodel) );
}

vec3 raymarch(vec3 origin, vec3 dir, mat4 invmodel, out bool hit) {
	float t = 0.0;
	for (int i = 0; i < steps; i++) {
		vec3 pos = origin + (dir * t);
		float h = map(pos, invmodel);
		if (h < MIN * t || h > MAX) {
			hit = h < MIN * t;
			return pos;
		}
		t += h;
	}
	// if max step count is reached, assume we would have hit something soon
	hit = true;
	return origin + (dir * t);
}

varying vec3 inout_pos; // world space fragment position

void vertex() {
	inout_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = color;
	// starting position for raymarch, in world coords. If outside bounding volume, start from surface of volume; if inside, start from camera
	vec3 start_pos = (FRONT_FACING ? inout_pos : CAMERA_POSITION_WORLD);
	// ray direction; from camera to frag position in world space
	vec3 raydir = normalize(inout_pos - CAMERA_POSITION_WORLD);
	// equivalent, but needs a matmul. Useful if world space frag position isn't available. VIEW: "Normalized vector from fragment position to camera (in view space)."
	//vec3 raydir = normalize(INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz;
	bool hit;
	// provide inverse model matrix to transform from "sdf local" to world space
	mat4 imm = inverse(MODEL_MATRIX);
	vec3 hitPoint = raymarch(start_pos, raydir, imm, hit); // hitPoint is in world space
	// map samples for normal also need to be transformed from local to world space
	NORMAL = calcNormal(hitPoint, imm);
	if (hit) {
		vec4 clip;
		if (set_depth) {
			clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hitPoint, 1.0);
		} else {
			clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(inout_pos, 1.0);
		}
		DEPTH = clip.z / clip.w; // puts depth in (0..1) range
	} else {
		ALPHA = 0.0;
		DEPTH = 1.0;
	}
}

// TODO: must overwrite light() for shadowing
