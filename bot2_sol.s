.data

# syscall constants
PRINT_STRING        = 4

# movement memory-mapped I/O
VELOCITY            = 0xffff0010
ANGLE               = 0xffff0014
ANGLE_CONTROL       = 0xffff0018

# coordinates memory-mapped I/O
BOT_X               = 0xffff0020
BOT_Y               = 0xffff0024

# planet memory-mapped I/O
PLANETS_REQUEST     = 0xffff1014

# scanning memory-mapped I/O
SCAN_REQUEST        = 0xffff1010
SCAN_SECTOR         = 0xffff101c

# gravity memory-mapped I/O
FIELD_STRENGTH      = 0xffff1100

# bot info memory-mapped I/O
SCORES_REQUEST      = 0xffff1018
ENERGY              = 0xffff1104

# debugging memory-mapped I/O
PRINT_INT           = 0xffff0080

# interrupt constants
SCAN_MASK           = 0x2000
SCAN_ACKNOWLEDGE    = 0xffff1204
ENERGY_MASK         = 0x4000
ENERGY_ACKNOWLEDGE  = 0xffff1208

# sector constants
SECTOR_HALF         = 18
SECTOR_SIZE         = 37
SECTORS_PER_ROW     = 8
NUM_SECTORS         = 64

# strategy constants

# there's nothing special about these numbers
# (except that they're all powers of two) ...
# they were just derived from trial and error

DUST_FIELD_STRENGTH = 8
CHASE_VELOCITY      = 4
DUST_WAIT_CYCLES    = 8192
CHASE_ITERATIONS    = 2048

# global variables

scan_done:
	.word 0

dust:
	.space 256

planets:
	.space 32
	
.text

# align ################################################################
#
# aligns a bot in a coordinate, busy waiting till complete
# argument $a0: the target coordinate
# argument $a1: 0 for aligning in X, 1 for aligning in Y
#
## // in_y = 0 means align in X, in_y = 1 means align in Y
## void align(int target, int in_y) {
##     // 0xffff0020 is bot X, 0xffff0024 is bot Y
##     // since they're adjacent, we can treat as int array and get
##     // bot_coords[0] is X, bot_coords[1] is Y
##     int * bot_coords = (int *) 0xffff0020;
##
##     int base_angle = in_y * 90; // 0 for X, 90 for Y
##     int turn = (target < bot_coords[in_y]) * 180;
##     SET_ABSOLUTE_ANGLE(base_angle + turn);
## 
##     while (target != bot_coords[in_y]) {
##         // wait
##     }
## }

align:
	mul	$t0, $a1, 90		# base angle (0 for X, 90 for Y)
	mul	$a1, $a1, 4		# addressing int arrays

	lw	$t1, BOT_X($a1)		# bot coordinate
	slt	$t1, $a0, $t1		# target above or to the left
	mul	$t1, $t1, 180		# flip bot if needed
	add	$t1, $t0, $t1
	sw	$t1, ANGLE
	li	$t1, 1
	sw	$t1, ANGLE_CONTROL

align_loop:
	lw	$t1, BOT_X($a1)		# bot coordinate
	bne	$a0, $t1, align_loop

	jr	$ra


# align_planet #########################################################
#
# aligns with a planet in a coordinate, busy waiting till complete
# argument $a0: 0 for aligning in X, 1 for aligning in Y
#
## planet_info_t planets[2];
## 
## // in_y = 0 means align in X, in_y = 1 means align in Y
## void align_planet(int in_y) {
##     // 0xffff0020 is bot X, 0xffff0024 is bot Y
##     // since they're adjacent, we can treat as int array and get
##     // bot_coords[0] is X, bot_coords[1] is Y
##     int * bot_coords = (int *) 0xffff0020;
## 
##     // first two elements of planet_info_t are X and Y
##     // so same trick works for those
##     int * planet_coords = (int *) planets;
## 
##     int base_angle = in_y * 90; // 0 for X, 90 for Y
## 
##     while (true) {
##         PLANETS_REQUEST(planets);
##         if (planet_coords[in_y] == bot_coords[in_y]) {
##             return;
##         }
## 
##         // if planet is above us or to the left, we add 180 to base angle
##         int turn = (planet_coords[in_y] < bot_coords[in_y]) * 180;
##         SET_ABSOLUTE_ANGLE(base_angle + turn);
##     }
## }

align_planet:
	mul	$t0, $a0, 90		# base angle (0 for X, 90 for Y)
	mul	$a0, $a0, 4		# addressing int arrays

ap_loop:
	la	$t1, planets
	sw	$t1, PLANETS_REQUEST	# get updated coordinates
	lw	$t1, planets($a0)	# planet coordinate
	lw	$t2, BOT_X($a0)		# bot coordinate
	beq	$t1, $t2, ap_done

	slt	$t1, $t1, $t2		# planet above or to the left
	mul	$t1, $t1, 180		# flip bot if needed
	add	$t1, $t0, $t1
	sw	$t1, ANGLE
	li	$t1, 1
	sw	$t1, ANGLE_CONTROL
	j	ap_loop

ap_done:
	jr	$ra


# find_best_sector #####################################################
#
# scans all sections for the one with the most dust
# return $v0: the sector ID

find_best_sector:
	li	$t0, 0			# current sector to scan
	la	$a0, dust		# array to store into
	move	$t1, $a0		# current array position
	li	$v0, -1			# current best sector
	li	$v1, -1			# current best dust amount

fbs_loop:
	sw	$zero, scan_done
	sw	$t0, SCAN_SECTOR
	sw	$a0, SCAN_REQUEST

fbs_wait:
	lw	$t2, scan_done
	beq	$t2, 0, fbs_wait

	lw	$t2, 0($t1)		# dust in scanned sector
	ble	$t2, $v1, fbs_next	# if not better than current best
	move	$v0, $t0		# new best sector
	move	$v1, $t2		# new best dust amount

fbs_next:
	add	$t0, $t0, 1
	add	$t1, $t1, 4
	blt	$t0, 64, fbs_loop

	jr	$ra


# get_sector_center ####################################################
#
# gets the center coordinates for a sector
# argument $a0: the sector number
# return $v0: sector center X
# return $v1: sector center Y

get_sector_center:
	rem	$v0, $a0, SECTORS_PER_ROW
	mul	$v0, $v0, SECTOR_SIZE
	add	$v0, $v0, SECTOR_HALF

	div	$v1, $a0, SECTORS_PER_ROW
	mul	$v1, $v1, SECTOR_SIZE
	add	$v1, $v1, SECTOR_HALF

	jr	$ra


# pick_up_dust #########################################################
#
# gets the bot to pick up dust by traveling to it and activating field
# waits after activating field for dust to gather
# argument $a0: dust X
# argument $a1: dust Y

pick_up_dust:
	sub	$sp, $sp, 8
	sw	$ra, 0($sp)
	sw	$a1, 4($sp)		# dust Y

	li	$t0, 10
	sw	$t0, VELOCITY
	li	$a1, 0
	jal	align
	lw	$a0, 4($sp)		# dust Y
	li	$a1, 1
	jal	align

	sw	$zero, VELOCITY
	li	$t0, DUST_FIELD_STRENGTH
	sw	$t0, FIELD_STRENGTH

	li	$t0, 0

pud_wait:
	add	$t0, $t0, 1
	blt	$t0, DUST_WAIT_CYCLES, pud_wait

	lw	$ra, 0($sp)
	add	$sp, $sp, 8
	jr	$ra


# chase_planet #########################################################
#
# chases the bot's planet, sticks with it for some iterations, then returns

chase_planet:
	sub	$sp, $sp, 8
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)

	li	$t0, CHASE_VELOCITY
	sw	$t0, VELOCITY
	li	$s0, 0

cp_loop:
	li	$a0, 0
	jal	align_planet
	li	$a0, 1
	jal	align_planet

	la	$t0, planets
	sw	$t0, PLANETS_REQUEST

	lw	$t1, 0($t0)
	lw	$t2, BOT_X
	bne	$t1, $t2, cp_loop	# if not aligned in X

	lw	$t1, 4($t0)
	lw	$t2, BOT_Y
	bne	$t1, $t2, cp_loop	# if not aligned in Y

	add	$s0, $s0, 1
	blt	$s0, CHASE_ITERATIONS, cp_loop

	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	add	$sp, $sp, 8
	jr	$ra


# main #################################################################
#

main:
	sub	$sp, $sp, 4
	sw	$ra, 0($sp)

	sw	$zero, VELOCITY
	li	$t0, SCAN_MASK
	or	$t0, $t0, 1
	mtc0	$t0, $12

	jal	find_best_sector

	move	$a0, $v0
	jal	get_sector_center

	move	$a0, $v0
	move	$a1, $v1
	jal	pick_up_dust

	jal	chase_planet
	sw	$zero, VELOCITY
	sw	$zero, FIELD_STRENGTH

loop:
	j	loop

	# never reached, but included for completeness
	lw	$ra, 0($sp)
	add	$sp, $sp, 4
	jr	$ra


# interrupt handler ####################################################
#

.kdata				# interrupt handler data (separated just for readability)
chunkIH:	.space 8	# space for two registers
non_intrpt_str:	.asciiz "Non-interrupt exception\n"
unhandled_str:	.asciiz "Unhandled interrupt type\n"


.ktext 0x80000180
interrupt_handler:
.set noat
	move	$k1, $at		# Save $at                               
.set at
	la	$k0, chunkIH
	sw	$a0, 0($k0)		# Get some free registers                  
	sw	$v0, 4($k0)		# by storing them to a global variable     

	mfc0	$k0, $13		# Get Cause register                       
	srl	$a0, $k0, 2                
	and	$a0, $a0, 0xf		# ExcCode field                            
	bne	$a0, 0, non_intrpt         

interrupt_dispatch:			# Interrupt:                             
	mfc0	$k0, $13		# Get Cause register, again                 
	beq	$k0, 0, done		# handled all outstanding interrupts     

	and	$a0, $k0, SCAN_MASK	# is there a scan interrupt?                
	bne	$a0, 0, scan_interrupt

	# add dispatch for other interrupt types here.

	li	$v0, PRINT_STRING	# Unhandled interrupt types
	la	$a0, unhandled_str
	syscall 
	j	done

scan_interrupt:
	sw	$zero, SCAN_ACKNOWLEDGE	# acknowledge interrupt
	li	$k0, 1
	sw	$k0, scan_done		# set global variable
	j	interrupt_dispatch	# see if other interrupts are waiting

non_intrpt:				# was some non-interrupt
	li	$v0, PRINT_STRING
	la	$a0, non_intrpt_str
	syscall				# print out an error message
	# fall through to done

done:
	la	$k0, chunkIH
	lw	$a0, 0($k0)		# Restore saved registers
	lw	$v0, 4($k0)
.set noat
	move	$at, $k1		# Restore $at
.set at 
	eret
