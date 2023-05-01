extends Spatial

export var horizontalMouseSensitivity: float = 0.09
export var verticalMouseSensitivity: float = 0.06

export var pitchRange = [-90, 90]

export var tiltRange = [-8, 8]

var cameraZRotation: float = 0
var cameraXRotation = 0
var cameraYRotation = 0

var jumpAngle
var angleToJump
var angleSign

onready var player = get_parent()
onready var playerState = player.ps
onready var playerCamera = $playerCamera
onready var ani = $AnimationPlayer

onready var startingTranslate = self.translation

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ani.play("RESET")

func _process(delta):
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if playerState.currentState == player.State.SLIDING:
		ani.play("slide")
		if Input.is_action_pressed("right"):
			cameraZRotation = move_toward(cameraZRotation, tiltRange[0], 55 * delta)
		elif Input.is_action_pressed("left"):
			cameraZRotation = move_toward(cameraZRotation, tiltRange[1], 55 * delta)
	elif playerState.currentState == player.State.CROUCHING:
		ani.play("crouch")
	elif playerState.currentState == player.State.JUMPING:
		match playerState.previousState:
			player.State.WALLCLIMB, player.State.WALLCLING, player.State.WALLRUN:
				if player.jump:
					angleToJump = (-player.global_transform.basis.z).angle_to(player.jumpVector.slide(Vector3(0, 1, 0)))
					angleSign = (-player.global_transform.basis.z).signed_angle_to(player.jumpVector.slide(Vector3(0, 1, 0)), Vector3(0,-1,0))
					angleSign = sign(angleSign)
					if angleToJump < (PI/2 - player.maxWallJumpAngle) + player.maxWallJumpAngle:
						jumpAngle = angleToJump + 1
						#dont rotate camera in between the maxWallJumpAngle when facing the wall
					else:
						jumpAngle = 0
				else:
					if jumpAngle < angleToJump:
						player.rotate_object_local(Vector3(0, -1, 0), angleSign*angleToJump/15)
						jumpAngle += angleToJump/15
	else:
		ani.queue("RESET")
	
	if ((!Input.is_action_pressed("right") and !Input.is_action_pressed("left")) or playerState.currentState != player.State.SLIDING):
		cameraZRotation = move_toward(cameraZRotation, 0, 90 * delta)
	playerCamera.rotation_degrees.z = cameraZRotation
	

func _input(event):
	#mouse movement
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var xDelta = event.relative.y * horizontalMouseSensitivity
		var yDelta = event.relative.x * verticalMouseSensitivity
		player.rotate_object_local(Vector3(0, -1, 0), deg2rad(yDelta))
		cameraYRotation += yDelta
		
		if (cameraXRotation + xDelta > pitchRange[0] and cameraXRotation + xDelta < pitchRange[1]):
			self.rotate_object_local(Vector3(-1, 0, 0), deg2rad(xDelta))
			cameraXRotation += xDelta
