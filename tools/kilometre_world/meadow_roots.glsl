#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer Roots { vec4 roots[]; };
layout(set=0,binding=1,std430) buffer Tiles { vec4 tiles[]; };
layout(set=0,binding=2) uniform sampler2D heights;
layout(set=0,binding=3) uniform sampler2D weights;
layout(push_constant,std430) uniform Field { ivec4 window; vec4 bounds; } field;
uint hash(uint x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
float noise(uint x){return float(hash(x)&0xffffffu)/16777216.;}
void main(){
	uint i=gl_GlobalInvocationID.x;
	int count=field.window.z, side=field.window.w;
	if(i>=uint(count*side*side))return;
	int slot=int(i)/count;
	ivec2 cell=field.window.xy+ivec2(slot%side,slot/side);
	uint seed=hash(uint(cell.x)^hash(uint(cell.y))^hash(i%uint(count))^floatBitsToUint(field.bounds.w));
	// A low-discrepancy sequence avoids random bald spots. Changing density
	// appends stable roots to the same sequence in each world-space tile.
	uint tile_seed=hash(uint(cell.x)^hash(uint(cell.y))^floatBitsToUint(field.bounds.w));
	vec2 offset=fract(vec2(noise(tile_seed),noise(tile_seed+1u))+
		float(i%uint(count))*vec2(0.754877666,0.569840291));
	vec2 pos=(vec2(cell)+offset)*16.;
	vec2 uv=pos/1000.+0.5/1024.;
	bool valid=all(greaterThanEqual(pos,vec2(0.))) && all(lessThan(pos,vec2(1000.))) && noise(seed+2u)<textureLod(weights,uv,0.).r;
	float y=textureLod(heights,uv,0.).r;
	roots[2u*i]=vec4(pos.x,y,pos.y,1.);
	roots[2u*i+1u]=vec4(noise(seed+3u)*6.283185,1.,valid?float(slot):-1.,uintBitsToFloat(seed));
	if(i%uint(count)==0u){
		vec2 low=vec2(cell)*16.;
		tiles[2*slot]=vec4(low.x-1.,field.bounds.x-1.,low.y-1.,float(count));
		tiles[2*slot+1]=vec4(low.x+17.,field.bounds.y+2.,low.y+17.,float(slot*count));
	}
}
