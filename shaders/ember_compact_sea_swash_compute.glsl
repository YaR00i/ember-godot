#[compute]
#version 450
// Per-cell history of the existing field. Wave math stays in Swash's profile table.
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
struct Record { vec4 address; vec4 coast; };
layout(set = 0, binding = 0, std430) readonly buffer Records { Record records[]; };
layout(set = 0, binding = 1, std430) readonly buffer Table { vec2 profiles[2600]; vec2 phases[65]; };
layout(rgba32f, set = 0, binding = 2) uniform image2D state_image;
layout(r32f, set = 0, binding = 3) uniform image2D foam_image;
layout(push_constant, std430) uniform Settings { vec4 step; vec4 grain; vec4 border; } settings;

void main() {
    uint index = gl_GlobalInvocationID.x;
    if (index >= uint(settings.grain.w)) return;
    Record record = records[index];
    // Shared boundaries retain the current 20 Hz clock even on a 5 Hz region.
    vec2 history_step = record.coast.w > 0.5 ? settings.border.xy : settings.step.xy;
    int pixel = int(record.address.x);
    ivec2 size = imageSize(state_image);
    ivec2 point = ivec2(pixel % size.x, pixel / size.x);
    int phase_group = int(record.address.y);
    float distance = record.coast.x;
    int distance_group = int(round(distance + 23.5));
    vec2 profile = profiles[phase_group * 40 + distance_group];
    float surface = record.coast.z + 0.02 + settings.step.z + profile.x;
    float depth = surface - record.coast.y;
    float coverage = distance > 0.0 ? smoothstep(0.02, 0.20, depth) : 1.0;
    if (settings.step.w <= 0.001 && distance > 0.0) coverage = 0.0;
    float edge = 1.0 - smoothstep(0.05, 0.75, max(depth, 0.0));
    float grain = 0.80 + 0.20 * dot(record.address.zw, settings.grain.xy);
    float foam = settings.step.w > 0.001 ? (edge * 0.75 + profile.y) * coverage * grain : 0.0;
    vec4 previous = settings.grain.z > 0.5 ? vec4(0.0) : imageLoad(state_image, point);
    float wetness = distance > 0.0 ? max(max(previous.b - history_step.y, 0.0), coverage) : 0.0;
    float age = settings.grain.z > 0.5 ? 8.0 : imageLoad(foam_image, point).r;
    age = min(age + history_step.x, 8.0);
    if (phases[phase_group].x > 0.5 && distance <= phases[phase_group].y + 0.5 && profile.x > 0.12 && foam > 0.07) age = 0.0;
    imageStore(state_image, point, vec4(distance > 0.0 ? max(surface, record.coast.y + 0.025) : surface, clamp(foam, 0.0, 1.0), wetness, coverage));
    imageStore(foam_image, point, vec4(age));
}
