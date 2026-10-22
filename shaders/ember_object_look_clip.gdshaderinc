// Opt-in presentation boundary in shared object-local metres. Both shells use
// complementary tests, including the shadow pass. No TIME/camera-dependent noise.
uniform bool object_look_clip_enabled = false;
uniform vec4 object_look_plane = vec4(1.0,0.0,0.0,0.0);
uniform bool object_look_positive = false;
bool ember_object_look_discard(vec3 p) {
	float side=dot(p,object_look_plane.xyz)-object_look_plane.w;
	return object_look_clip_enabled && (object_look_positive ? side<0.0 : side>=0.0);
}
