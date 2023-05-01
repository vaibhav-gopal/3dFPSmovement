extends Spatial

var cameraXRotation = 0
var cameraYRotation = 0

onready var camera = $playerCamera

func _on_head_moveCamera(xCamRot, yCamRot):
	self.rotate_object_local(Vector3(0, -1, 0), deg2rad(yCamRot))
	cameraYRotation += yCamRot
	camera.rotate_object_local(Vector3(-1, 0, 0), deg2rad(xCamRot))
	cameraXRotation += xCamRot

func _on_head_moveViewport(x, y, z):
	self.transform.origin = (Vector3(x, y, z))
