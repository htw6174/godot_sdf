/* testing and reference, TODO make a common header */
shader_type spatial;
render_mode cull_disabled;

// too large will expand shapes, but too small will be more expensive and may reveal 'misses'
#define MIN 0.00015
// too large will be more expensive, too small will limit ray penetraion into volume
#define MAX 100.0

uniform vec3 color : source_color;
uniform float period = 3.0;
uniform vec3 extents = vec3(4.0);

vec2 hash2(vec2 p) {
	vec2 r = mat2(vec2(127.1, 311.7), vec2(269.5, 183.3)) * p;
	return fract( sin( r )*43758.5453 );
}

// Credit for sdf utility functions goes to iq https://iquilezles.org/articles/distfunctions/
float sdSphere(in vec3 p, float r) {
	return length(p) - r;
}

// volumeless line from origin to b
// returns (distance from line, progress along line at closest distance)
vec2 sdLineOri(in vec3 p, in vec3 b )
{
    float h = clamp( dot(p,b)/dot(b,b), 0.0, 1.0 );
    return vec2( length(p-h*b), h );
}

vec3 opRepLim( in vec3 p, in float s, in vec3 lima, in vec3 limb )
{
    return p-s*clamp(round(p/s),lima,limb);
}

float mapGrassBlade(in vec3 p, in float h, in vec2 r) {
	vec2 rand = hash2(r);
	vec2 offset = rand * 0.4 - 0.4;
	vec3 qos = vec3(p.x, p.y, p.z);
	qos.xz += offset.xy; // shift within cell
	qos.xz = reflect( qos.xz, normalize(-1.0+2.0*rand) ); // random rotation
	qos.x -= 0.03*qos.y*qos.y; // bendiness
	qos.x *= 5.0; // flatten on one axis
	vec2 se = sdLineOri(qos, vec3(0.0, h, 0.0));
	float gr = 0.3*sqrt(1.0-0.99*se.y); // thin tip, wide base
	float d = se.x - gr;
	return d;
}

float mapGrassField(in vec3 p) {
	float h = 10.0;
	p *= h;
	vec2 r = floor(p.xz + vec2(0.5, 0.5)); // TODO: only works when period is 1
	p = opRepLim(p, period, -extents, extents);
	//p.xz = fract(p.xz);
	float d = mapGrassBlade(p, h, r);
	d /= h;
	return d / h;
}

float map(vec3 pos) {
	float d = mapGrassField(pos);
	//d = sdSphere(pos, 1.0);
	return d;
}

// https://iquilezles.org/articles/normalsSDF
vec3 calcNormal( in vec3 pos )
{
    vec2 e = vec2(1.0,-1.0)*0.5773;
    const float eps = 0.0005;
    return normalize( e.xyy*map( pos + e.xyy*eps ) + 
					  e.yyx*map( pos + e.yyx*eps ) + 
					  e.yxy*map( pos + e.yxy*eps ) + 
					  e.xxx*map( pos + e.xxx*eps ) );
}

vec3 raymarch(vec3 origin, vec3 dir, out bool hit) {
	float t = 0.0;
	for (int i = 0; i < 256; i++) {
		vec3 pos = origin + (dir * t);
		float h = map(pos);
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

varying vec3 inout_pos;

void vertex() {
	inout_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = color;
	// starting position for raymarch, in local coords. If outside bounding volume, start from surface of volume; if inside, start from camera
	vec3 start_pos = (FRONT_FACING ? inout_pos : CAMERA_POSITION_WORLD) - NODE_POSITION_WORLD;
	vec3 world_pos = inout_pos;
	// ray direction; from camera to frag position in world space
	vec3 raydir = normalize(inout_pos - CAMERA_POSITION_WORLD);
	// equivalent, but needs a matmul. Useful if world space frag position isn't available. VIEW: "Normalized vector from fragment position to camera (in view space)."
	//vec3 raydir = normalize(INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz;
	bool hit;
	vec3 hitPoint = raymarch(start_pos, raydir, hit);
	NORMAL = calcNormal(hitPoint);
	if (hit) {
		//DEPTH = distance(CAMERA_POSITION_WORLD, hitPoint + NODE_POSITION_WORLD);
		//DEPTH = (VIEW_MATRIX * PROJECTION_MATRIX * vec4(hitPoint + NODE_POSITION_WORLD, 1.0)).z;
		//vec4 ndc = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
		vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hitPoint + NODE_POSITION_WORLD, 1.0);
		DEPTH = clip.z / clip.w; // puts depth in (0..1) range
	} else {
		ALPHA = 0.0;
		DEPTH = 1.0;
	}
	//ALBEDO = vec3(FRAGCOORD.z);
	//ALBEDO = vec3(FRAGCOORD.z);
	//ALBEDO = NODE_POSITION_WORLD + vec3(UV, 0.0);
}

// TODO: must overwrite light() for shadowing
