extends Spatial

export var horizontalMouseSensitivity: float = 0.09
export var verticalMouseSensitivity: float = 0.09

export var thirdPersonPitchRange = [-50, 50]
export var firstPersonPitchRange = [-90, 90]

var cameraXRotation = 0
var cameraYRotation = 0
var isThirdPerson = false
signal moveCamera(xCamRot, yCamRot)
signal moveViewport(x, y, z)
signal notification(title, text, time, delay, type)

onready var player = get_parent()
onready var worldCamera = $worldCamera
onready var thirdPersonCameraPivot = $pivot
onready var thirdPersonCamera = $pivot/thirdPerson
onready var playerViewportContainer = get_node("../viewportContainer")

export var maxThirdPersonZoom = [3, 7]
export var zoomIncrement = 0.5

export var maxWorldCameraFov = [50, 120]
export var fovIncrement = 5

func _process(delta):
	if isThirdPerson:
		if Input.is_action_just_pressed("zoomOut"):
			thirdPersonCamera.translation.z = min(thirdPersonCamera.translation.z + zoomIncrement, maxThirdPersonZoom[1])
			emit_signal("notification", "zoom", String(thirdPersonCamera.translation.z) + "/" + String(maxThirdPersonZoom[1]), 1, 0, "zoom")
		elif Input.is_action_just_pressed("zoomIn"):
			thirdPersonCamera.translation.z = max(thirdPersonCamera.translation.z - zoomIncrement, maxThirdPersonZoom[0])
			emit_signal("notification", "zoom", String(thirdPersonCamera.translation.z) + "/" + String(maxThirdPersonZoom[1]), 1, 0, "zoom")
	else:
		if Input.is_action_just_pressed("zoomIn"):
			worldCamera.fov = min(worldCamera.fov + fovIncrement, maxWorldCameraFov[1])
			emit_signal("notification", "FOV", String(worldCamera.fov), 1, 0, "fov")
		elif Input.is_action_just_pressed("zoomOut"):
			worldCamera.fov = max(worldCamera.fov - fovIncrement, maxWorldCameraFov[0])
			emit_signal("notification", "FOV", String(worldCamera.fov), 1, 0, "fov")

func _input(event):
	#mouse movement
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var xDelta = event.relative.y * horizontalMouseSensitivity
		var yDelta = event.relative.x * verticalMouseSensitivity
		player.rotate_object_local(Vector3(0, -1, 0), deg2rad(yDelta))
		cameraYRotation += yDelta
		
		if (!isThirdPerson):
			if (cameraXRotation + xDelta > firstPersonPitchRange[0] and cameraXRotation + xDelta < firstPersonPitchRange[1]):
				self.rotate_object_local(Vector3(-1, 0, 0), deg2rad(xDelta))
				cameraXRotation += xDelta
				emit_signal("moveCamera", xDelta, yDelta)
			else:
				emit_signal("moveCamera", 0, yDelta)
		else:
			if (cameraXRotation + xDelta > thirdPersonPitchRange[0] and cameraXRotation + xDelta < thirdPersonPitchRange[1]):
				thirdPersonCameraPivot.rotate_object_local(Vector3(-1, 0, 0), deg2rad(xDelta))
				cameraXRotation += xDelta
				emit_signal("moveCamera", xDelta, yDelta)
			else:
				emit_signal("moveCamera", 0, yDelta)

func _on_playerEntity_changeViewType(thirdPerson):
	if thirdPerson:
		playerViewportContainer.hide()
		worldCamera.current = false
		thirdPersonCamera.current = true
		isThirdPerson = true
	else:
		playerViewportContainer.show()
		worldCamera.current = true
		thirdPersonCamera.current = false
		isThirdPerson = false

#passes signal from player to playerCamera
func _on_playerEntity_moveViewport(x, y, z):
	emit_signal("moveViewport", x, y, z)
