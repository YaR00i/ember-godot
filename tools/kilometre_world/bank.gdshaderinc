// Distance is in compact-map voxels; time samples the same run-up profile as Ember.
uniform sampler2D bank_floor : filter_linear, repeat_disable;
uniform sampler2D bank_profile : filter_linear, repeat_disable;
uniform float bank_level;
uniform float bank_runup_m = 0.175;
uniform float bank_period = 9.0;
uniform float bank_test_seconds = -1.0;

vec2 bank_wave(vec2 p,float seconds) {
	vec2 uv=p/1000.+vec2(0.5/1024.);
	float step_uv=1./1024.;
	float y=textureLod(bank_floor,uv,0.).r;
	if(abs(y-bank_level)>1.2 || bank_runup_m<=0.)return vec2(0.);
	vec2 slope=vec2(textureLod(bank_floor,uv+vec2(step_uv,0),0.).r-textureLod(bank_floor,uv-vec2(step_uv,0),0.).r,
		textureLod(bank_floor,uv+vec2(0,step_uv),0.).r-textureLod(bank_floor,uv-vec2(0,step_uv),0.).r)*0.512;
	float distance_vox=(y-bank_level)*16./max(length(slope),0.055);
	if(distance_vox < -24. || distance_vox > 16.)return vec2(0.);
	float phase=fract(seconds/bank_period+sin(dot(p,vec2(0.13,0.079)))*0.035);
	vec2 at=vec2((distance_vox+24.)/40.,phase);
	return textureLod(bank_profile,(at*127.+0.5)/128.,0.).rg;
}
