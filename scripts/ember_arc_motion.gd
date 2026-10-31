extends RefCounted
## One pure arc calculation for combat hops and cosmetic pickup motion.
static func position_at(start: Vector3, destination: Vector3, weight: float, height: float) -> Vector3:
	return start.lerp(destination,weight) + Vector3.UP * sin(PI*weight) * height
