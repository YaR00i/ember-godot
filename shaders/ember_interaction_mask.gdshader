shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, depth_test_disabled;
// A single focused object uses this reference for the union of its meshes.
// Outline depth testing still occludes the result behind world geometry.
stencil_mode write, compare_always, 64;
void fragment() {
	ALPHA = 0.0;
}
