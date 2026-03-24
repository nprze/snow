package world

import fmt "core:fmt"
import snow "snow:bridge"

cubeCollider :: struct {
	position:   snow.Vec3,
	halfLenght: f32,
	rotation:   snow.Vec3,
}
sphereCollider :: struct {
	position: snow.Vec3,
	radius:   f32,
}
collider :: union {
	cubeCollider,
	sphereCollider,
}

cubeVertices: [8]snow.Vec3 = {
	{-0.5, -0.5, -0.5},
	{0.5, -0.5, -0.5},
	{0.5, -0.5, 0.5},
	{-0.5, -0.5, 0.5},
	{-0.5, 0.5, -0.5},
	{0.5, 0.5, -0.5},
	{0.5, 0.5, 0.5},
	{-0.5, 0.5, 0.5},
}

objectColliders: []collider
lastCollider: u32 = 0
maxColliders: u32 = 1024

add_collider :: proc(c: collider) -> u32 {
	objectColliders[lastCollider] = c
	lastCollider += 1
	return lastCollider - 1
}
physics_init :: proc() {
	objectColliders = make([]collider, int(maxColliders))
}
physics_update :: proc() {
	for i in objectColliders {
		for j in objectColliders {
			if i != j {
				fmt.println("more than one")
			}
		}
	}
}
