extends KinematicBody

const raycast = preload("res://other/raycastDot.tscn")

export var walkSpeed:float = 10
export var walkAccel: float = 7.5
export var decel: float = 10
export var maxSlopeAngle: float = 40

export var sprintSpeed: float = 14
export var sprintAccel: float = 10
var isSprinting: bool = false

export var jumpPower: float = 20
export var jumpBufferTime: float = 0.1
var jumpDirection: Vector3 = Vector3.ZERO
var isJumping: bool = false

var playerBasis = transform.basis
var currentVelocity: Vector3 = Vector3.ZERO
var previousVelocity: Vector3 = Vector3.ZERO

var currentStatePosition: Vector3 = Vector3.ZERO
var previousStatePosition: Vector3 = Vector3.ZERO

export var mass: float = 4
export var maxGravitySpeed: float = 80.0
export var gravity: float = 10.0
var gravityDirection: Vector3 = Vector3.DOWN.normalized()
var gravityForce: float = mass * gravity
var applyGravity: bool = true

var spaceState
onready var mouseRayLength: float = get_viewport().get_camera().far

var isThirdPerson: bool = false
signal moveViewport(x, y, z)
signal changeViewType(thirdPerson)

onready var worldCamera = $head/worldCamera
onready var thirdPersonCamera = $head/pivot/thirdPerson
onready var playerViewportContainer = $viewportContainer
onready var flashlight = playerViewportContainer.get_node("playerViewport/rotationHelper/playerCamera/Arm/flashlight")
onready var jumpBuffer = $feetCollisionShape/jumpBuffer

func _ready():
	_player_init()

func _player_init():
	#lock mouse in the center
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	#set jump buffer wait time from exported variable
	jumpBuffer.wait_time = jumpBufferTime
	currentStatePosition = transform.origin

#MAIN USER LOOP FUNCTIONS ------------------------------------------------------
func _process_input():
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Input.is_action_just_pressed("flashlight"):
		if flashlight.is_visible_in_tree():
			flashlight.hide()
		else:
			flashlight.show()
	if Input.is_action_pressed("sprint"):
		isSprinting = true
	else:
		isSprinting = false
	if Input.is_action_just_pressed("thirdPerson"):
		if playerViewportContainer.is_visible_in_tree():
			isThirdPerson = true
			emit_signal("changeViewType", true)
		else:
			isThirdPerson = false
			emit_signal("changeViewType", false)

func _physics_process(delta):
	spaceState = get_world().direct_space_state
	_process_input()

	if (currentVelocity != Vector3.ZERO):
		emit_signal("moveViewport", transform.origin.x, transform.origin.y, transform.origin.z)

#MOVEMENT HELPER FUNCTIONS -----------------------------------------------------
func _get_direction() -> Vector3:
	var out = Vector3.ZERO
	var forward = Input.get_action_strength("forward") - Input.get_action_strength("backward")
	var right = Input.get_action_strength("right") - Input.get_action_strength("left")
	var up = Input.get_action_strength("jump")
	#update player directions/basis
	playerBasis = transform.basis
	out -= playerBasis.z * forward #forward is -z in godot
	out += playerBasis.x * right
	#return direction user wants to mvoe
	if (Input.is_action_just_pressed("jump")):
		if (is_on_floor()):
			isJumping = true
		else:
			jumpBuffer.start()
		jumpDirection = (playerBasis.y * up)
	return out.normalized()
	
#HELPER FUNCTIONS --------------------------------------------------------------
func _mouse_intersect_ray():
	var cameraToUse = worldCamera
	if isThirdPerson: 
		cameraToUse = thirdPersonCamera
	var mousePosition = get_viewport().get_mouse_position()
	var mouseRayOrigin = cameraToUse.project_ray_origin(mousePosition)
	var mouseRayNormal = (cameraToUse.project_ray_normal(mousePosition) * mouseRayLength) + mouseRayOrigin
	return spaceState.intersect_ray(mouseRayOrigin, mouseRayNormal, [self], 1)
	
func _draw_dot(pos):
	var raycastDot = raycast.instance()
	get_tree().current_scene.add_child(raycastDot)
	raycastDot.transform.origin = pos

#SIGNALS -----------------------------------------------------------------------
