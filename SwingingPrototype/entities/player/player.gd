extends KinematicBody

const raycast = preload("res://other/raycastDot.tscn")

export var walkSpeed:float = 10
export var walkAccel: float = 7.5

export var sprintSpeed: float = 14
export var sprintAccel: float = 10

export var decel: float = 10

export var maxSlopeAngle: float = 40

export var jumpPower: float = 20
export var jumpBufferTime: float = 0.1

var playerBasis = transform.basis
var currentVelocity: Vector3 = Vector3.ZERO
var previousVelocity: Vector3 = Vector3.ZERO

var jumpDirection: Vector3 = Vector3.ZERO

var currentStatePosition: Vector3 = Vector3.ZERO
var previousStatePosition: Vector3 = Vector3.ZERO

export var mass: float = 4

export var maxGravitySpeed: float = 80.0
export var gravity: float = 10.0
var gravityDirection: Vector3 = Vector3.DOWN.normalized()
var gravityForce: float = 0

var tensionDirection: Vector3
var tensionForce: float = 0
export var damping = 0.999

var isSprinting: bool = false
var isJumping: bool = false
var goingToJump: bool = false
var applyGravity: bool = true

enum state {DEFAULT, GRAPPLING}
var currentState = state.DEFAULT

var hookpoints = []
var hookpointsPlaced = [false, false]
var maxHookpointDistance: float = 30
const leftHook: int = 0
const rightHook: int = 1

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
	if Input.is_key_pressed(16777237): #shift
		if (Input.is_action_just_pressed("leftHook")):
			_attach_hook(leftHook)
		if (Input.is_action_just_pressed("rightHook")):
			_attach_hook(rightHook)
		if (Input.is_action_just_pressed("releaseHooks")):
			currentState = state.DEFAULT
			hookpoints.clear()
			hookpointsPlaced = [false, false]

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
			goingToJump = true
		jumpDirection = (playerBasis.y * up)
	return out.normalized()

func _physics_process(delta):
	spaceState = get_world().direct_space_state
	_process_input()
	
	var direction = _get_direction()
	previousStatePosition = currentStatePosition
	previousVelocity = currentVelocity
	currentStatePosition = _update_movement(direction, delta)
	match currentState:
		state.DEFAULT:
			currentVelocity = _move_player(currentVelocity)
		state.GRAPPLING:
			currentVelocity = _move_player(currentVelocity)
			if hookpointsPlaced[leftHook]:
				hookpoints[leftHook].playerPosition = currentStatePosition
			if hookpointsPlaced[rightHook]:
				hookpoints[rightHook].playerPosition = currentStatePosition

	if (currentVelocity != Vector3.ZERO):
		emit_signal("moveViewport", transform.origin.x, transform.origin.y, transform.origin.z)

func _update_movement(dir: Vector3, dt: float):
	gravityForce = mass * gravity
	match currentState:
		state.DEFAULT:
			currentVelocity = _calculate_basic_movement(dir, dt)
		state.GRAPPLING:
			currentVelocity = Vector3.ZERO
			if hookpointsPlaced[leftHook]:
				currentVelocity = _swing_movement(leftHook, dt)
			if hookpointsPlaced[rightHook]:
				currentVelocity = _swing_movement(rightHook, dt)
	var movementDelta = currentVelocity * dt
	return currentStatePosition + movementDelta

func _calculate_basic_movement(dir: Vector3, dt: float):
	var out: Vector3 = Vector3(previousVelocity.x, 0, previousVelocity.z)
	var speed = walkSpeed
	var accel = walkAccel
	
	if (isSprinting):
		speed = sprintSpeed
		accel = sprintAccel
	if !(currentVelocity.normalized().dot(dir) > 0):
		accel = decel
	
	out = out.linear_interpolate(dir * speed, accel * dt)
	out.y = previousVelocity.y
	
	if (isJumping or (goingToJump and is_on_floor())):
		out += jumpDirection * jumpPower
		goingToJump = false
		isJumping = false
	elif (!is_on_floor() and applyGravity):
		out = _calculate_gravity(out, dt)
	return out

func _swing_movement(whichHook, dt: float):
	var out: Vector3 = previousVelocity
	out = _calculate_gravity(out, dt)

	var anchorPos: Vector3 = hookpoints[whichHook].position
	var bobPos: Vector3 = hookpoints[whichHook].playerPosition

	var auxillaryMovementDelta: Vector3 = out * dt #suggest removing * dt
	var distanceAfterGravity: float = anchorPos.distance_to(bobPos + auxillaryMovementDelta)

	var inclinationAngle = gravityDirection.angle_to(bobPos - anchorPos)

	if (distanceAfterGravity > hookpoints[whichHook].ropeLength || is_equal_approx(distanceAfterGravity, hookpoints[whichHook].ropeLength)):
		tensionDirection = (anchorPos - bobPos).normalized()
		tensionForce = gravityForce * cos(inclinationAngle)
		#no matter the speed of currentVelocity, the centripetal force will pull it back ; SO DONT WORRY
		var centripetalForce = (mass * out.length_squared()) / hookpoints[whichHook].ropeLength
		tensionForce += centripetalForce
		out += tensionDirection * tensionForce * dt
#		out *= damping
	
	var newPosition = currentStatePosition + out * dt
	var distance = anchorPos.distance_to(newPosition)
	
	print(distance, " ", hookpoints[whichHook].ropeLength)
	if (distance <= hookpoints[whichHook].ropeLength):
		return out
	else:
		var pointOnPivot = _get_point_on_pivot(anchorPos, newPosition, hookpoints[whichHook].ropeLength) * dt
		out += (pointOnPivot - out) * dt
		return out

func _calculate_gravity(vel: Vector3, dt: float):
	if (vel.y >= -maxGravitySpeed):
		vel.y = max(vel.y - (gravityForce * dt), -maxGravitySpeed)
	else:
		vel.y = min(vel.y + (gravityForce * dt), -maxGravitySpeed)
	return vel

func _move_player(velocity1, velocity2 = Vector3.ZERO): #velocity2 is optional (for two grappling hooks)
	return move_and_slide(velocity1, playerBasis.y, false, 4, maxSlopeAngle)

#HELPER FUNCTIONS --------------------------------------------------------------
func _player_init():
	#lock mouse in the center
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	#set jump buffer wait time from exported variable
	jumpBuffer.wait_time = jumpBufferTime
	
	currentStatePosition = transform.origin

func _mouse_intersect_ray():
	var cameraToUse = worldCamera
	if isThirdPerson: 
		cameraToUse = thirdPersonCamera
	var mousePosition = get_viewport().get_mouse_position()
	var mouseRayOrigin = cameraToUse.project_ray_origin(mousePosition)
	var mouseRayNormal = (cameraToUse.project_ray_normal(mousePosition) * mouseRayLength) + mouseRayOrigin
	return spaceState.intersect_ray(mouseRayOrigin, mouseRayNormal, [self], 1)

func _get_point_on_pivot(start: Vector3, end: Vector3, distanceFromPivot: float) -> Vector3:
	return start + (distanceFromPivot * (end - start).normalized())
	
func _draw_dot(pos):
	var raycastDot = raycast.instance()
	get_tree().current_scene.add_child(raycastDot)
	raycastDot.transform.origin = pos

func _attach_hook(whichHook):
	var mouseRayIntersection = _mouse_intersect_ray()
	if !mouseRayIntersection.empty():
		var hookpointDistance = mouseRayIntersection.position.distance_to(transform.origin)
		if (!hookpointsPlaced[whichHook] && hookpointDistance <= maxHookpointDistance):
			hookpoints.remove(whichHook)
			hookpoints.resize(2)
			hookpoints.insert(whichHook, Hookpoint.new(mouseRayIntersection.position, transform.origin, whichHook))
			currentState = state.GRAPPLING
			hookpointsPlaced[whichHook] = true
			
			# REMOVE THESE LINES
			#currentVelocity = Vector3.ZERO 
			#currentStatePosition = transform.origin
		_draw_dot(mouseRayIntersection.position)

class Hookpoint:
	var position: Vector3 = Vector3.ZERO
	var playerPosition: Vector3 = Vector3.ZERO
	var ropeLength: float = 0
	var index: float = 0
	
	func _init(startPos: Vector3, endPos: Vector3, whichIndex):
		position = startPos
		playerPosition = endPos
		ropeLength = (startPos - endPos).length()
		index = whichIndex
#SIGNALS -----------------------------------------------------------------------
func _on_jumpBuffer_timeout():
	goingToJump = false
