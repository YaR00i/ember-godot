shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;
#define EMBER_MATERIAL_TRANSPARENT
#include "res://shaders/ember_material_surface.gdshaderinc"
