extends Spatial

onready var anchor = $anchor
onready var bob = $pendulum

export var mass: float = 20
export var gravity: float = 10

export var isRopeRigid = true

export var damping = 0.992
export var gravityDamping = 0.999

var ropeLength: float

var bobStartingPosition: Vector3
var bobStartingPositionSet: bool

var gravityDirection: Vector3
var tensionDirection: Vector3

var tangentDirection: Vector3
var pendulumSideDirection: Vector3

var tensionForce: float = 0
var gravityForce: float = 0

var currentVelocity: Vector3 = Vector3.ZERO

var currentStatePosition: Vector3 = Vector3.ZERO
var previousStatePosition: Vector3 = Vector3.ZERO

func _ready():
	bobStartingPosition = bob.transform.origin
	bobStartingPositionSet = true
	_init_pendulum()

func _physics_process(delta):
	_process_input()
	previousStatePosition = currentStatePosition
	currentStatePosition = _pendulum_update(currentStatePosition, delta) #CHANGE TO RETURN THE STATE POSITION
	_move_bob(currentStatePosition)

#HELPER FUNCTIONS --------------------------------------------------------------

func _init_pendulum():
	ropeLength = anchor.transform.origin.distance_to(bob.transform.origin)
	_reset_pendulum_forces()

func _reset_pendulum_position():
	if (bobStartingPositionSet):
		_move_bob(bobStartingPosition)
	else:
		_init_pendulum()

func _reset_pendulum_forces():
	currentVelocity = Vector3.ZERO
	currentStatePosition = bob.transform.origin

func _move_bob(newBobPosition):
	bob.transform.origin = newBobPosition
	currentStatePosition = newBobPosition

func _get_point_on_path(start: Vector3, end: Vector3, distanceFromPivot: float) -> Vector3:
	return start + (distanceFromPivot * (end - start).normalized())

#MAIN LOOP ---------------------------------------------------------------------

func _pendulum_update(currentStatePos: Vector3, dt: float):
	gravityForce = mass * gravity
	gravityDirection = Vector3.DOWN.normalized()
	currentVelocity += gravityDirection * gravityForce * dt
	
	var anchorPos: Vector3 = anchor.transform.origin
	var bobPos: Vector3 = currentStatePos
	
	var auxillaryMovementDelta: Vector3 = currentVelocity * dt #suggest removing * dt
	var distanceAfterGravity: float = anchorPos.distance_to(bobPos + auxillaryMovementDelta)
	
	var inclinationAngle = gravityDirection.angle_to(bobPos - anchorPos)
	print(currentVelocity)
	if (distanceAfterGravity > ropeLength || is_equal_approx(distanceAfterGravity, ropeLength)):
		tensionDirection = (anchorPos - bobPos).normalized()

		#DONT NEED THIS CODE BLOCK
#		var pendulumSideRotation = Quat(Vector3(0, PI/2, 0))
#		pendulumSideDirection = pendulumSideRotation.xform(tensionDirection)
#		pendulumSideDirection.y = 0
#		pendulumSideDirection.normalized()
#		tangentDirection = (-1 * tensionDirection.cross(pendulumSideDirection)).normalized()

		tensionForce = gravityForce * cos(inclinationAngle)
		var centripetalForce = (mass * currentVelocity.length_squared()) / ropeLength
		tensionForce += centripetalForce

		currentVelocity += tensionDirection * tensionForce * dt

		currentVelocity *= damping
	else:
		currentVelocity *= gravityDamping
	
	var movementDelta = currentVelocity * dt
	var distance = anchorPos.distance_to(currentStatePosition + movementDelta)
	if (distance <= ropeLength):
		return currentStatePosition + movementDelta
	else:
		return _get_point_on_path(anchorPos, currentStatePosition + movementDelta, ropeLength)

func _process_input():
	if Input.get_action_strength("forward"):
		currentVelocity -= bob.transform.basis.z * 2
	if Input.get_action_strength("left"):
		currentVelocity -= bob.transform.basis.x * 2
	if Input.get_action_strength("right"):
		currentVelocity += bob.transform.basis.x * 2
	if Input.get_action_strength("backward"):
		currentVelocity += bob.transform.basis.z * 2
