extends KinematicBody

#VELOCITY / FORCE VARIABLES
var velocity: Vector3 = Vector3.ZERO
var force: Vector3 = Vector3.ZERO
export var mass: float = 1
export var dragConstant: float = 1
export var defaultFrictionConstant: float = 9
var frictionConstant: float = defaultFrictionConstant
var movementVector: Vector3 = Vector3.ZERO #force vector for player input forces
var additionalVector: Vector3 = Vector3.ZERO #force vector for everything thats not player forces, and gravity

#JUMP VARIABLES
export var jumpStrength: float = 1300
export var jumpHoldMultiplier: float = 0.6
var onJumpGravityCancellationMultiplier: float = 0.6
var jumpBuffer: float = 0
var jumpBufferCollision
var jumpBufferDistance: float = 3
const jumpDirection: Vector3 = Vector3.UP #jump direction, relative to player
var jumpVector: Vector3

#INPUT VARIABLES
var forward: float = 0
var right: float = 0
var sprint: float = 0
var crouchAndSlide: float = 0
var jump: float = 0
var jumpHold: float = 0

#MOVEMENT VARIABLES
export var moveStrength: float = 60
export var sprintMultiplier: float = 1.5
export var airSpeedMultiplier: float = 0.15
export var crouchSpeedMultiplier: float = 0.4
var slidingFrictionDivisor: float = 11
var slidingMovementDivisor: float = 15
var minimumSlidingMultiplier: float = 1.1
var minimumKeepSlidingMultiplier: float = 0.85

#GRAVITY / FLOOR VARIABLES
export var gravityStrength: float = 45
var defaultGravityDirection: Vector3 = Vector3.DOWN
var gravityDirection: Vector3 = defaultGravityDirection #gravity direction, global transform not relative
const floorDirection: Vector3 = Vector3.UP #floor normal, global transform not relative
var maxSlopeAngle: float = 7*PI/36 - PI/50 #>~35 degrees
var maxSlideAngle: float = PI/3 #60 degrees
var lastSlide

#WALL VARIABLES
var minWallInputAngle: float = PI/3 #min angle which you can move towards with your inputs without detaching from the wall
var wallGravityMultiplier: float = 0.2
var wallClingMultiplier: float = 0.05
var wallFrictionConstant: float = frictionConstant / 5
var maxWallJumpAngle: float = PI/6
var wallForce: float = 2
var horizontalDirectionAlongWall
var verticalDirectionAlongWall

var wallClimbVelocity: Vector3
var wallClimbBaseSpeed: float = 5
var wallClimbClampSpeed = [4, 10]
var wallClimbStoppingSpeed = 2 #speed which wallclimb stops
var wallClimbMinimumSpeed = -12 #minimum speed needed to enter wallclimb while falling
var wallClimbDecelerationTime: float = 0.7 #time it takes to decelerate back to stopping speed
var wallClimbDecelerationStep: float
var wallClimbMaximumAngle: float = PI/2 #maximum angle which character must face wall in order to wallclimb

var wallRunHorizontalMinimumSpeed: float = 4
var wallRunStoppingSpeed = 4.5 #speed which wallrun stops
var wallRunVerticalMinimumSpeed: float = -20
var wallRunGravityMultiplier: float = 0.05
var wallRunClampSpeed = [6, 12]
var wallRunBaseSpeed = wallRunClampSpeed[0] - wallRunHorizontalMinimumSpeed
var wallRunSpeed: float
var wallRunDecelerationStep: float = 0.02
var wallRunVerticalCancellationMultiplier: float = 0.75

onready var wallClimbRaycastCollider = $wallClimbColliderCheck
onready var wallClimbRaycastSpaceBuffer = $wallClimbSpaceBuffer
onready var wallClimbRaycastFeet = $wallClimbFeetCheck

#PHYSICS DIRECT SPACE VARIABLE FOR RAYCASTING
onready var directState = get_world().direct_space_state

#STATE CLASSES / VARIABLES
#state machine functions:
#	should be able to access other state functions / movements, specifically the move commands and jump commands
#	each state should have possible states it can connect to, and each state should have an "entrance" condition(s) which must be true to enter a state
class stateMachine:
	var previousState
	var currentState setget updateState
	var player
	func _init(s, p):
		previousState = s
		currentState = s
		player = p
	func updateState(ns):
		previousState = currentState
		currentState = ns
		print(player.names[currentState])
		#Universal actions to perform once when exiting a function
		match previousState:
			State.SLIDING:
				player.frictionConstant = player.defaultFrictionConstant
		#Universal actions to perform once when entering a function
		match currentState:
			State.SLIDING:
				player.frictionConstant = player.defaultFrictionConstant / player.slidingFrictionDivisor
			State.JUMPING:
				player.velocity += -player.velocity.project(player.gravityDirection) * player.onJumpGravityCancellationMultiplier
			State.WALLCLIMB:
				player.wallClimbVelocity = player.verticalDirectionAlongWall * clamp(player.velocity.dot(player.verticalDirectionAlongWall) + player.wallClimbBaseSpeed,player.wallClimbClampSpeed[0], player.wallClimbClampSpeed[1])
				player.wallClimbDecelerationStep = (player.wallClimbVelocity.length() - player.wallClimbStoppingSpeed) / (ProjectSettings.get_setting("physics/common/physics_fps") * player.wallClimbDecelerationTime)
			State.WALLRUN:
				player.wallRunSpeed = clamp(player.velocity.project(player.horizontalDirectionAlongWall).length() + player.wallRunBaseSpeed, player.wallRunClampSpeed[0], player.wallRunClampSpeed[1])
				player.velocity += -player.velocity.project(player.gravityDirection) * player.wallRunVerticalCancellationMultiplier

enum State {WALKING, CROUCHING, JUMPING, FREEFALL, SLIDING, WALLCLING, WALLCLIMB, WALLRUN}
const names = ['WALKING', 'CROUCHING', 'JUMPING', 'FREEFALL', 'SLIDING', 'WALLCLING', 'WALLCLIMB', 'WALLRUN']
var ps = stateMachine.new(State.WALKING, self)

#-----------------MAIN LOOP--------------------------------------------------
#----------------------------------------------------------------------------

func _physics_process(delta):
	
	updateCommonVariables()
	processInput()
	processNextState()
	calculateForce()
	applyDampingAndForce(delta)
	velocity = move_and_slide(velocity, floorDirection, false, 4, maxSlopeAngle)

#-----------------MAIN FUNCTIONS---------------------------------------------
#----------------------------------------------------------------------------

func updateCommonVariables():
	#this is first in the physics process function call stack b/c some varibles here are used to determine the next state, and as such are used in later functions as well
	lastSlide = get_last_slide_collision()
	if is_on_wall():
		horizontalDirectionAlongWall = floorDirection.cross(lastSlide.normal).normalized()
		verticalDirectionAlongWall = lastSlide.normal.cross(horizontalDirectionAlongWall).normalized()
	#for variables you want to update every frame AFTER one frame on the selected state
	match ps.currentState:
		State.JUMPING:
			jumpBuffer = 0

func processInput():
	forward = Input.get_action_strength("forward") - Input.get_action_strength("back")
	right = Input.get_action_strength("right") - Input.get_action_strength("left")
	sprint = Input.get_action_strength("run")
	crouchAndSlide = Input.is_action_pressed("crouch")
	jump = Input.is_action_just_pressed("jump")
	jumpHold = Input.get_action_strength("jump")

func processNextState():
	match ps.currentState:
		#base states are walking and falling, for ground and air respectively, all states should have a condition to these
		#IMPORTANT: When a state switches, the NEW STATE ACTIONS/FUNCTIONS will only be performed ONE PHYSICS FRAME LATER,
		#	when the REST OF THE _PHYSICS_PROCESS function has FINISHED CALLING and a NEW LOOP HAS STARTED
		#	also note that priority in state switching matters
		State.WALKING:
			if is_on_floor():
				if jump:
					ps.currentState = State.JUMPING
				#defaultMoveStrength/defaultFrictionConstant gives you the asymptote (max move speed) introduced by the damping functions
				elif crouchAndSlide && (velocity.length() > (moveStrength/defaultFrictionConstant) * minimumSlidingMultiplier):
					ps.currentState = State.SLIDING
				elif crouchAndSlide:
					ps.currentState = State.CROUCHING
			else:
				ps.currentState = State.FREEFALL
		State.JUMPING:
			if !is_on_floor():
				if velocity.dot(-gravityDirection.normalized()) <= 0: #checks if velocity magnitude in the direction of the jump is less than 0
					ps.currentState = State.FREEFALL
				elif is_on_wall():
					if sprint and checkWallRunSpeedAndAngle():
						ps.currentState = State.WALLRUN
					elif jumpHold and (-global_transform.basis.z).angle_to(-lastSlide.normal) <= wallClimbMaximumAngle:
						ps.currentState = State.WALLCLIMB
					else:
						ps.currentState = State.WALLCLING
			else:
				ps.currentState = State.WALKING
		State.FREEFALL: #REMINDER: in freefall if ur on a slope greater than the maxSlopeAngle (move and slide function) or if ur falling
			if !is_on_floor():
				if is_on_wall():
					if sprint and checkWallRunSpeedAndAngle():
						ps.currentState = State.WALLRUN
					elif (velocity.dot(verticalDirectionAlongWall) >= wallClimbMinimumSpeed or checkRaycastHeadFeet()) and jumpHold and (-global_transform.basis.z).angle_to(-lastSlide.normal) <= wallClimbMaximumAngle:
						#made sure previous states weren't wall related so you wouldn't get a random boost on walls in certain situations
						#used so u can wall climb while ur slightly falling or when u just hit the edge of a wall to climb up
						if ps.previousState != State.WALLCLIMB and ps.previousState != State.WALLCLING and ps.previousState != State.WALLRUN:
							ps.currentState = State.WALLCLIMB
						else:
							ps.currentState = State.WALLCLING
					else:
						ps.currentState = State.WALLCLING
				elif jump:
					jumpBufferCollision = directState.intersect_ray(global_transform.origin, global_transform.origin - (floorDirection * jumpBufferDistance), [self])
					jumpBuffer = 1 if jumpBufferCollision else 0
			else:
				if jumpBuffer:
					var collider = jumpBufferCollision.collider_id if jumpBufferCollision else NAN #check if raycast from before and the floor collision are the same object
					if lastSlide.collider_id == collider:
						ps.currentState = State.JUMPING
				else:
					ps.currentState = State.WALKING
		State.CROUCHING:
			if is_on_floor():
				if !crouchAndSlide:
					ps.currentState = State.WALKING
				elif jump:
					ps.currentState = State.JUMPING
			else:
				ps.currentState = State.FREEFALL
		State.SLIDING:
			if is_on_floor():
				if jump:
					ps.currentState = State.JUMPING
				elif (velocity.length() < (moveStrength/defaultFrictionConstant)*minimumKeepSlidingMultiplier):
					if crouchAndSlide:
						ps.currentState = State.CROUCHING
					else:
						ps.currentState = State.WALKING
				elif !crouchAndSlide:
					ps.currentState = State.WALKING
			elif is_on_wall():
				if !crouchAndSlide:
					ps.currentState = State.WALLCLING
				elif jump:
					ps.currentState = State.JUMPING
			else:
				ps.currentState = State.FREEFALL
		State.WALLCLING:
			if !is_on_wall():
				if is_on_floor():
					ps.currentState = State.WALKING
				else:
					ps.currentState = State.FREEFALL
			else:
				if jump:
					ps.currentState = State.JUMPING
				elif crouchAndSlide and get_last_slide_collision(): 
					if get_last_slide_collision().normal.angle_to(floorDirection) <= maxSlideAngle: #on a 'wall' (non-climbable slope) less than maxSlideAngle
						ps.currentState = State.SLIDING
		State.WALLCLIMB:
			if !is_on_wall():
				ps.currentState = State.FREEFALL
			elif is_on_wall():
				if (checkRaycastHeadFeet() and jumpHold):
					ps.currentState = State.WALLCLIMB
				elif !jumpHold or (velocity.dot(verticalDirectionAlongWall) <= wallClimbStoppingSpeed):
					ps.currentState = State.WALLCLING
		State.WALLRUN:
			if !is_on_wall():
				if is_on_floor():
					ps.currentState = State.WALKING
				else:
					ps.currentState = State.FREEFALL
			elif is_on_wall():
				if jump:
					ps.currentState = State.JUMPING
				elif crouchAndSlide and get_last_slide_collision(): 
					if get_last_slide_collision().normal.angle_to(floorDirection) <= maxSlideAngle: #on a 'wall' (non-climbable slope) less than maxSlideAngle
						ps.currentState = State.SLIDING
				elif !sprint or abs(velocity.dot(horizontalDirectionAlongWall)) <= wallRunStoppingSpeed or velocity.dot(verticalDirectionAlongWall) < wallRunVerticalMinimumSpeed:
					if checkRaycastHeadFeet():
						ps.currentState = State.WALLCLIMB
					else:
						ps.currentState = State.WALLCLING

func checkRaycastHeadFeet():
	#raycast on head to check for space if you can actually climb up, raycast on feet to check if it is colliding with the object ur on, then check another long range raycast on head to make sure its not colliding with the object ur on
	if !wallClimbRaycastSpaceBuffer.is_colliding() and wallClimbRaycastFeet.is_colliding() and lastSlide.collider_id == wallClimbRaycastFeet.get_collider().get_instance_id():
		if wallClimbRaycastCollider.is_colliding() and wallClimbRaycastCollider.get_collider().get_instance_id() != lastSlide.collider_id or !wallClimbRaycastCollider.is_colliding():
			return true
		else:
			return false
	else:
		return false

func checkWallRunSpeedAndAngle():
	if abs(velocity.dot(horizontalDirectionAlongWall)) >= wallRunHorizontalMinimumSpeed and velocity.project(horizontalDirectionAlongWall).dot(-global_transform.basis.z) >= 0 and velocity.dot(verticalDirectionAlongWall) >= wallRunVerticalMinimumSpeed:
		return true
	else:
		return false

func calculateForce():
	calculateMovement()
	#state based gravity calculation
	match ps.currentState:
		State.WALLCLING, State.WALLCLIMB:
			force = (gravityDirection.normalized() * gravityStrength * mass * wallGravityMultiplier)
		State.WALLRUN:
			force = (gravityDirection.normalized() * gravityStrength * mass * wallRunGravityMultiplier)
		_:
			force = (gravityDirection.normalized() * gravityStrength * mass * range_lerp((ps.currentState == State.JUMPING and jumpHold) as int, 0, 1, 1, jumpHoldMultiplier))
	force += movementVector + additionalVector #additional vector is currently not immplemented

func calculateMovement():
	#returns the current character basis rotated due to the current slope/ramp up to a certain angle ; this rotated movement ONLY AFFECTS PLAYER INPUT
	#also changes the gravity direction so it faces the slope when touching
	var cross ; var angle ; var slopedBasis
	if lastSlide && lastSlide.normal.angle_to(floorDirection) <= maxSlopeAngle:
		cross = lastSlide.normal.cross(floorDirection).normalized()
		angle = lastSlide.normal.angle_to(floorDirection)
		slopedBasis = global_transform.basis.rotated(cross, -angle).orthonormalized()
		gravityDirection = -lastSlide.normal if ps.currentState != State.SLIDING else defaultGravityDirection
	else:
		slopedBasis = global_transform.basis
		gravityDirection = defaultGravityDirection
	
	#state based movement
	match ps.currentState:
		State.WALLCLING:
			movementVector = -lastSlide.normal * wallForce
			var inputVector = global_transform.basis.xform(Vector3(right, 0, -forward)).normalized()
			if inputVector.angle_to(lastSlide.normal) >= minWallInputAngle:
				movementVector += (inputVector * moveStrength).project(horizontalDirectionAlongWall) * wallClingMultiplier
			else:
				movementVector += inputVector * moveStrength * wallClingMultiplier
		State.WALLRUN:
			movementVector = -lastSlide.normal * wallForce
			var inputVector = global_transform.basis.xform(Vector3(0, 0, -forward)).project(horizontalDirectionAlongWall).normalized()
			if velocity.dot(inputVector) >= 0:
				velocity += (wallRunSpeed * inputVector - velocity.project(horizontalDirectionAlongWall))
				wallRunSpeed = move_toward(wallRunSpeed, wallRunStoppingSpeed, wallRunDecelerationStep)
			else:
				movementVector = lastSlide.normal * wallForce
		State.WALLCLIMB:
			movementVector = -lastSlide.normal
			velocity += (wallClimbVelocity - velocity.project(verticalDirectionAlongWall))
			wallClimbVelocity = wallClimbVelocity.move_toward(Vector3.ZERO, wallClimbDecelerationStep)
		_:
			movementVector = (slopedBasis.xform(Vector3(right, 0, -forward)).normalized() * moveStrength)
	
	#state based movement multipliers
	match ps.currentState:
		State.WALKING:
			movementVector *= range_lerp(sprint, 0, 1, 1, sprintMultiplier)
		State.CROUCHING:
			movementVector *= crouchSpeedMultiplier * range_lerp(sprint, 0, 1, 1, sprintMultiplier)
		State.JUMPING, State.FREEFALL:
			movementVector *= airSpeedMultiplier
		State.SLIDING:
			movementVector /= slidingMovementDivisor
	
	#previous state based jump modifiers
	if ps.currentState == State.JUMPING:
		#use the regular global_transform.basis for jump direction transformation, as the jump shouldn't be sloped/slanted unless ur on a wall
		match ps.previousState:
			State.WALLCLING, State.WALLRUN:
				if is_on_wall() and jump:
					jumpOffNormal(lastSlide.normal, 0.4, maxWallJumpAngle)
			State.SLIDING:
				if is_on_wall() and jump:
					jumpOffNormal(lastSlide.normal, 0.5, maxWallJumpAngle)
				elif is_on_floor() and jump:
					jumpOffNormal(get_floor_normal(), 0.6, PI/2)
			_:
				if is_on_floor() and (jump or jumpBuffer):
					movementVector += (jumpDirection.linear_interpolate(get_floor_normal(), 0.2).normalized() * jumpStrength)

func jumpOffNormal(normal: Vector3, interpolationToNormal: float, maxHorizontalAngle: float):
	var jumpWallDirection = global_transform.basis.xform(jumpDirection).linear_interpolate(normal, interpolationToNormal)
	var forwardBasis = -global_transform.basis.z if normal.dot(-global_transform.basis.z) >= 0 else (-global_transform.basis.z).bounce(normal)
	var angleToBasis = jumpWallDirection.slide(jumpDirection).signed_angle_to(forwardBasis, -jumpDirection)
	jumpVector = jumpWallDirection.rotated(-jumpDirection, clamp(angleToBasis, -maxHorizontalAngle, maxHorizontalAngle)).normalized() * jumpStrength
	movementVector += jumpVector

func applyDampingAndForce(delta):
	#calculating the acceleration (force divided by mass) then subtracting some value of friction dependent on velocity
	#tldr: velocity doesn't increase infinitely, introducing an asymptote via friction ; different frictions/damping based on whether ur on the ground or not
	if (is_on_floor()):
		velocity += ((force/mass) - (velocity * frictionConstant)) * delta
	elif ps.currentState == State.WALLCLING or ps.currentState == State.WALLCLIMB or ps.currentState == State.WALLRUN:
		velocity += ((force/mass) - (velocity * wallFrictionConstant)) * delta
	else:
		velocity += ((force/mass) - (velocity * dragConstant)) * delta

func printPhysicsParameters():
	var parameters = ["Velocity: ",velocity.x, velocity.y, velocity.z, "\t Force: ", force.x, force.y, force.z]
	print(parameters)
