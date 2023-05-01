extends KinematicBody

var velocity: Vector3 = Vector3.ZERO
var force: Vector3 = Vector3.ZERO
export var mass: float = 1
export var dragConstant: float = 1
export var defaultFrictionConstant: float = 9
var frictionConstant: float = defaultFrictionConstant

var jump: float = 0
var jumpHold: float = 0
export var jumpHoldMultiplier: float = 0.6
var jumpBuffer: float = 0
var jumpBufferCollision
var jumpBufferDistance: float = 3.5

var forward: float = 0
var right: float = 0
var sprint: float = 0
var crouch: float = 0
var sliding: float = 0
#introduce state system to clean things up?

export var jumpStrength: float = 1300
export var gravityStrength: float = 45
export var defaultMoveStrength: float = 60
var moveStrength: float = defaultMoveStrength
export var sprintMultiplier: float = 1.5
export var airSpeedMultiplier: float = 0.15
export var crouchSpeedMultiplier: float = 0.4
var defaultGravityDirection: Vector3 = Vector3.DOWN
var gravityDirection: Vector3 = defaultGravityDirection #gravity direction, global transform not relative
var jumpDirection: Vector3 = Vector3.UP #jump direction, relative to player
const floorDirection: Vector3 = Vector3.UP #floor normal, global transform not relative
var movementVector: Vector3 = Vector3.ZERO #Vector to check if player is idle/falling ; force vector for everything but gravity
var maxSlopeAngle: float = 7*PI/36 - PI/50 #>~35 degrees


onready var directState = get_world().direct_space_state

#-----------------MAIN LOOP--------------------------------------------------
#----------------------------------------------------------------------------

func _physics_process(delta):
	processInput()
	#calculating the acceleration (force divided by mass) then subtracting some value of friction dependent on velocity
	#tldr: velocity doesn't increase infinitely, introducing an asymptote via friction ; different frictions/damping based on whether ur on the ground or not
	calculateForce()
	if (is_on_floor()):
		velocity += ((force/mass) - (velocity * frictionConstant)) * delta
	else:
		velocity += ((force/mass) - (velocity * dragConstant)) * delta
	#stop on slope parameter on move and slide = false, doesn't work properly at all, implemented solution in calculate force function
	velocity = move_and_slide(velocity, floorDirection, false, 4, maxSlopeAngle) 
	print(velocity.length())
	#printPhysicsParameters()

#-----------------MAIN FUNCTIONS---------------------------------------------
#----------------------------------------------------------------------------

func processInput():
	processJumpInput()
	forward = Input.get_action_strength("forward") - Input.get_action_strength("back")
	right = Input.get_action_strength("right") - Input.get_action_strength("left")
	sprint = Input.get_action_strength("run") * is_on_floor() as int
	processCrouchInput()

func processCrouchInput():
	crouch = Input.is_action_pressed("crouch") and is_on_floor()
	#defaultmovestrength/defaultfrictionconstant gives us the asymptote, or the max walk speed; this is an asymptote of the function where force/mass and damping is calculated
	if crouch && (velocity.length() > (defaultMoveStrength/defaultFrictionConstant) * 1.1 or (sliding and velocity.length() > (defaultMoveStrength/defaultFrictionConstant/1.1))):
		frictionConstant = defaultFrictionConstant / 11
		moveStrength = defaultMoveStrength / 15
		sliding = 1
	else:
		frictionConstant = defaultFrictionConstant
		moveStrength = defaultMoveStrength
		sliding = 0

func processJumpInput():
	#jumping / jump buffer code -----------
	if (is_on_floor()):
		#this variable is to check if when pressing the jump buffer, the object below the player is the same
		var collider = jumpBufferCollision.collider_id if jumpBufferCollision else NAN
		if Input.is_action_just_pressed("jump"):
			jump = 1
		else:
			jump = 0
		if (jumpBuffer && get_last_slide_collision().collider_id == collider):
			jump = 1
		jumpBuffer = 0
	else:
		if (Input.is_action_just_pressed("jump")):
			#calculates the ray direction which is opposite to the floor direction/normal, floor direction is not relative to player so it does not need to get transformed by basis
			jumpBufferCollision = directState.intersect_ray(global_transform.origin, global_transform.origin - (floorDirection * jumpBufferDistance), [self])
			jumpBuffer = 1 if jumpBufferCollision else 0
		jump = 0
	#jumping longer code ------------
	#a bit confusing but it works; deactivates when falling, and stays active (feedback loop) as long as jump as been active once
	#to check if rising, which is relative to jump direction, project velocity to jump direction, which shows the magnitude of velocity that is jumping, if its greater than 0
	jumpHold = jump if jump else jumpHold
	jumpHold = Input.get_action_strength("jump") if (jumpHold && (velocity.dot(jumpDirection.normalized()) > 0 or is_on_floor())) else 0

func calculateForce():
	#returns the current character basis rotated due to the current slope/ramp up to a certain angle ; this rotated movement ONLY AFFECTS PLAYER INPUT, which makes it good for keeping realism
	#also changes the gravity direction so it faces the slope when touching
	var slide = get_last_slide_collision()
	var cross ; var angle ; var slopedBasis
	if slide && slide.normal.angle_to(floorDirection) <= maxSlopeAngle:
		cross = slide.normal.cross(floorDirection).normalized()
		angle = slide.normal.angle_to(floorDirection)
		slopedBasis = global_transform.basis.rotated(cross, -angle).orthonormalized()
		gravityDirection = -slide.normal if !sliding else defaultGravityDirection
	else:
		slopedBasis = global_transform.basis
		gravityDirection = defaultGravityDirection
	#seperate movement input and jump input into the movement force vector, useful for checking when player is idle or falling
	#also use the regular global_transform.basis for jump direction transformation, as the jump shouldn't be sloped/slanted unless ur on a wall
	movementVector = (slopedBasis.xform(Vector3(right, 0, -forward)).normalized() * moveStrength * lerp(1, sprintMultiplier, sprint * lerp(1, 0, sliding)) * lerp(airSpeedMultiplier, 1, is_on_floor() as int) * range_lerp(crouch * lerp(1, 0, sliding), 0, 1, 1, crouchSpeedMultiplier))
	movementVector += (global_transform.basis.xform(jumpDirection).normalized() * jumpStrength * jump)
	#map jumphold (0-1) to (1-0.5) ; lessens when jumpHold is higher, same value when jumpHold is zero ; this of course ASSUMES that gravity force vector is the main part of the jump vector, don't know how to fix this for now
	force = (gravityDirection.normalized() * gravityStrength * mass * range_lerp(jumpHold, 0, 1, 1, jumpHoldMultiplier)) + movementVector

func printPhysicsParameters():
	var printStuff = ["Velocity: ",velocity.x, velocity.y, velocity.z, "\t Force: ", force.x, force.y, force.z]
	print(printStuff)

#-----------------SET GET / HELPER FUNCTIONS---------------------------------
#----------------------------------------------------------------------------
