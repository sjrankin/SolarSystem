shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// A flat grid (a subdivided plane whose local x/z run from -1 to 1) whose vertices are pushed
// down by the summed gravity wells of the Sun and planets.
//
// Each body contributes a softened 1/r well:  depth_i = D_i / sqrt((d / eps_i)^2 + 1)
// where d is the distance in AU from the body to the grid point. Wells are summed, so they merge
// into saddle points between nearby bodies, as the real potential does.
//
// Adaptive resolution: the plane's vertices are remapped each frame so the mesh is centred on
// the camera target, covers `half_extent` scene units, and is denser near the centre
// (`concentration`). Zooming in shrinks `half_extent`, so the same vertex budget gets finer.
// The drawn grid lines are fixed in the world and switch spacing by octaves as you zoom.

const int MAX_BODIES = 12;

// xy: body position in AU (x, z); z: softening length in AU; w: display depth in scene units.
uniform vec4 bodies[MAX_BODIES];
uniform int body_count = 0;
uniform bool linear_scale = false;
uniform float linear_units_per_au = 20.0;
uniform float compressed_units = 60.0;

uniform vec2 center = vec2(0.0);
uniform float half_extent = 520.0;
uniform float concentration = 2.0;

uniform float grid_base_spacing = 8.5;
uniform float grid_level = 0.0;

uniform float max_depth = 60.0;
uniform vec3 shallow_color : source_color = vec3(0.25, 0.5, 1.0);
uniform vec3 deep_color : source_color = vec3(1.0, 0.45, 0.8);

varying float v_depth;
varying float v_edge;
varying vec2 v_world;

// Inverts the scene's distance mapping so wells are evaluated at true AU separations.
vec2 scene_to_au(vec2 p) {
	float r = length(p);
	if (r < 1e-6) {
		return vec2(0.0);
	}
	float r_au = linear_scale ? r / linear_units_per_au : pow(r / compressed_units, 2.0);
	return p / r * r_au;
}

float total_depth(vec2 au) {
	float depth = 0.0;
	for (int i = 0; i < MAX_BODIES; i++) {
		if (i >= body_count) {
			break;
		}
		float d = length(au - bodies[i].xy) / bodies[i].z;
		depth += bodies[i].w / sqrt(d * d + 1.0);
	}
	return depth;
}

void vertex() {
	vec2 u = VERTEX.xz;
	// sinh mapping: spacing is smallest at the centre and grows toward the edge.
	vec2 world = center + half_extent * sinh(concentration * u) / sinh(concentration);
	v_world = world;
	v_edge = max(abs(u.x), abs(u.y));
	v_depth = total_depth(scene_to_au(world));
	// The node has no x/z offset or scale, so local x/z are world x/z.
	VERTEX = vec3(world.x, -v_depth, world.y);
}

// 1 on a grid line, 0 between lines; `spacing` is in world units.
float grid_line(vec2 world, float spacing) {
	vec2 c = world / spacing;
	vec2 g = abs(fract(c - 0.5) - 0.5) / max(fwidth(c), vec2(1e-5));
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	float level = floor(grid_level);
	float f = grid_level - level;
	float spacing = grid_base_spacing * exp2(level);
	// Lines of the next-coarser octave are always shown; the finer octave fades out as it nears.
	float line = max(grid_line(v_world, spacing) * (1.0 - f), grid_line(v_world, spacing * 2.0));
	float t = clamp(v_depth / max_depth, 0.0, 1.0);
	float fade = 1.0 - smoothstep(0.7, 1.0, v_edge);
	ALBEDO = mix(shallow_color, deep_color, sqrt(t));
	ALPHA = line * mix(0.3, 0.9, t) * fade;
}
