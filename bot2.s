.data

three:	.float	3.0
five:	.float	5.0
PI:	.float	3.141592
F180:	.float  180.0


.align 2
scan_occurred: .space 1

.align 2
planet_info: .space 32

.align 2
scan_data: .space 64*4

.align 2
planet_data: .space 32

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

.text

main:
	# your code goes here
	# for the interrupt-related portions, you'll want to
	# refer closely to example.s - it's probably easiest
	# to copy-paste the relevant portions and then modify them
	# keep in mind that example.s has bugs, as discussed in section

					# ENABLE INTERRUPTS
	li	$t0, SCAN_MASK		# scan interrupt enable bit
	or	$t0, $t0, 1		# global interrupt bit
	mtc0	$t0, $12		# set interrupt mask to status reg
	lw	$t1, scan_occurred
	li	$t1, 0
	sw	$t1, scan_occurred
step1:
	j	scan_sectors
step2:
					# calculate the sector coords
	li	$t1, 0			# reset t1 to store row_idx
	li	$t2, 8			# reset t2 to store col_idx
	div	$t5, $t2
	mfhi	$t2
	mflo	$t1
	li	$t3, 36
	mul	$t1, $t1, $t3		
	add	$t1, $t1, 18		# y	
	mul	$t2, $t2, $t3
	add	$t2, $t2, 18		# x
	j	move_to_sector
step4:					# need to turn on gravitation... leave it till later. 
	#	li	$t1, 6
	#	sw	$t1, FIELD_STRENGTH
	j	move_to_orbit


step3:	# if planet1 is moving toward spim bot, then stop waiting and move spimbot to it
	
	li	$t1, 1
	sw	$t1, FIELD_STRENGTH

	
	li	$t4, 0			# dist1
	li	$t5, 0			# dist2
	li	$t6, 0			# first
	li	$t7, 0			# diff
	li	$t8, 0			# bot-p2 dist
wait_approach:
	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
wa_con1:
	blt	$t7, $0, wa_con2
	j	wa_in_loop
wa_con2:
	bge	$t8, $0, wa_con3	#end_wait_approach
	j	wa_in_loop
wa_con3:
	li	$t9, -5
	bgt	$t8, $t9, end_wait_approach
wa_in_loop:
	
	lw	$a0, 16($t1)		# p2_x
	lw	$t2, BOT_X
	sub	$a0, $a0, $t2
	lw	$a1, 20($t1)		# p2_y
	lw	$t2, BOT_Y
	sub	$a1, $a1, $t2
	jal	euclidean_dist
	move	$t8, $v0
	
	lw	$a0, 0($t1)		# a0 p1_x
	lw	$t2, BOT_X		# t2 b_x
	sub	$a0, $a0, $t2
	lw	$a1, 4($t1)		# a1 p1_y
	lw	$t2, BOT_Y		# t2 b_y
	sub	$a1, $a1, $t2
	jal	euclidean_dist
	
#	lw	$a0, 16($t1)
#	lw	$a1, 20($t1)
#	jal	euclidean_dist
#	move	$t8, $v0		# p2_x^2 + p2_y^2
	
	bne	$t6, $0, dist2
dist1:
	li	$t6, 1
	move	$t4, $v0
	sub	$t8, $t8, $t4
	sub	$t7, $t4, $t5
	j	wait_approach
dist2:
	li	$t6, 0
	move	$t5, $v0
	sub	$t8, $t8, $t5
	sub	$t7, $t5, $t4
	j	wait_approach

end_wait_approach:
	j	step4

infinite:
	
	j	infinite

# To scan every sector and retrieve the one with most dust
scan_sectors:
	li	$t1, 0
	li	$t5, 0			# max
	li	$t6, 0			# num_of_dust
for1:
	li	$t2, 63
	beq	$t1, $t2, end_for1
	sw	$t1, SCAN_SECTOR
	la	$t2, scan_data
	mul	$t7, $t1, 4
	add	$t2, $t2, $t7
	sw	$t2, SCAN_REQUEST
wait_scan:
	lw	$t3, scan_occurred
	li	$t4, 1
	beq	$t3, $t4, finish_scan
	j	wait_scan
finish_scan:
	lw	$t3, scan_occurred
	li	$t3, 0
	sw	$t3, scan_occurred

	mul	$t7, $t1, 4
	add	$t2, $t2, $t7
	lw	$t2, 0($t2)		# still buggy
if1:
	ble	$t2, $t6, end_if1
	move	$t5, $t1		# t5 holds max dust sector num
	move	$t6, $t2
end_if1:
	add	$t1, $t1, 1
	j	for1
end_for1:
	j	step2


move_to_sector:
	lw	$t3, BOT_Y($0)	# curr ycoord of bot
	bgt	$t3, $t1, up
down:
	li	$t3, 90
	sw	$t3, ANGLE($0)	# to go down
	li	$t3, 1
	sw	$t3, ANGLE_CONTROL($0)
	li	$t3, 10			
	sw	$t3, VELOCITY($0)	# set speed to 5
	j	bot1_while_vert
up:
	li	$t3, 270
	sw	$t3, ANGLE($0)	# to go up
	li	$t3, 1
	sw	$t3, ANGLE_CONTROL($0)
	li	$t3, 10		
	sw	$t3, VELOCITY($0)	# set speed to 5
bot1_while_vert:
	lw	$t3, BOT_Y($0)	# curr ycoord of bot
	beq	$t3, $t1, bot1_end_while_vert
	j	bot1_while_vert
bot1_end_while_vert:
	li	$t3, 0
	sw	$t3, VELOCITY($0)

	lw	$t3, BOT_X
	bgt	$t3, $t2, left
right:
	li	$t3, 0
	sw	$t3, ANGLE($0)	# to go right
	li	$t3, 1
	sw	$t3, ANGLE_CONTROL($0)
	li	$t3, 10			
	sw	$t3, VELOCITY($0)	# set speed to 5
	j	bot1_while_horz

left:
	li	$t3, 180
	sw	$t3, ANGLE($0)	# to go left
	li	$t3, 1
	sw	$t3, ANGLE_CONTROL($0)
	li	$t3, 10			
	sw	$t3, VELOCITY($0)	# set speed to 5

bot1_while_horz:
	lw	$t3, BOT_X($0)	# curr xcoord of bot
	beq	$t3, $t2, bot1_end_while_horz
	j	bot1_while_horz
bot1_end_while_horz:
	li	$t3, 0
	sw	$t3, VELOCITY($0)
	j	step4


mtp_check:
	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	move	$a0, $t8		# p1_x
	lw	$t2, BOT_X		# b_x
	sub	$a0, $a0, $t2
	move	$a1, $t7
	lw	$t2, BOT_Y
	sub	$a1, $a1, $t2
	jal	euclidean_dist
	move	$t2, $v0		# dist between p1 and bot
	lw	$t3, 12($t1)
	li	$t4, 20
	div	$t3, $t4
	mflo	$t3
	bgt	$t2, $t3, mtp_loop
	li	$t1, 0
	sw	$t1, VELOCITY
	li	$t1, 2
	sw	$t1, FIELD_STRENGTH
	j	main



move_to_orbit:
	lw	$t4, BOT_X
	lw	$t5, BOT_Y
	blt	$t5, 150, mto_up
mto_down:
	blt	$t4, 150, mto_down_left
	j	mto_down_right

	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	lw	$t2, 0($t1)
	lw	$t3, 4($t1)
	lw	$t6, 8($t1)
	add	$t6, $t6, 150
	beq	$t6, $t2, mto_down_proceed
	j	mto_down
mto_up:
	blt	$t4, 150, mto_up_left
	j	mto_up_right

	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	lw	$t2, 0($t1)
	lw	$t6, 8($t1)
	li	$t4, 150
	sub	$t6, $t4, $t6
	beq	$t6, $t2, mto_up_proceed
	j	mto_up

mto_down_left:
	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	lw	$t2, 16($t1)
	lw	$t3, 20($t1)
	lw	$t7, 8($t1)
	lw	$t8, 12($t1)

	li	$t4, 150
	sub	$t7, $t4, $t7
	li	$t9, 2
	div	$t8, $t9
	mflo	$t8
	move	$t9, $t7
	sub	$t7, $t7, $t8	
	li	$t8, 150
	beq	$t3, $t9, mto_proceed1
	j	mto_down_left

mto_down_right:
	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	lw	$t2, 16($t1)
	lw	$t3, 20($t1)
	lw	$t8, 8($t1)

	li	$t4, 150
	add	$t8, $t4, $t8
	li	$t7, 150
	beq	$t2, $t8, mto_proceed1
	j	mto_down_right

mto_up_left:
	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	lw	$t2, 16($t1)
	lw	$t3, 20($t1)
	lw	$t8, 8($t1)

	li	$t4, 150
	sub	$t8, $t4, $t8
	lw	$t7, 12($t1)
	li	$t9, 1
	div	$t7, $t9
	mul	$t7, $t7, 1
	mflo	$t7
	move	$t9, $t8
	#	add	$t8, $t8, $t7
	li	$t7, 150
	beq	$t2, $t9, mto_proceed1
	j	mto_up_left

mto_up_right:
	la	$t1, planet_info
	sw	$t1, PLANETS_REQUEST
	lw	$t2, 16($t1)
	lw	$t3, 20($t1)
	lw	$t7, 8($t1)
	lw	$t9, 12($t1)

	li	$t4, 150
	add	$t7, $t4, $t7
	add	$t7, $t7, 10
	li	$t8, 170
	beq	$t3, $t8, mto_proceed1
	j	mto_up_right


mto_proceed1:
	move	$t3, $t8		# dest_y
	move	$t2, $t7		# dest_x	
	li	$t1, 6
	sw	$t1, FIELD_STRENGTH
	j	mto_move

mto_proceed2:
	move	$t2, $t8		# dest_x
	move	$t3, $t7		# dest_y	
	li	$t1, 6
	sw	$t1, FIELD_STRENGTH
	j	mto_move

mto_move:
	j	mto_loop



mto_loop:
	lw	$t4, BOT_X
	lw	$t5, BOT_Y

mto_go_horz_choice:
	blt	$t2, $t4, mto_go_left
	j	mto_go_right

mto_go_left:
	lw	$t4, BOT_X
	beq	$t4, $t2, mto_go_vert_choice
	li	$t4, 180
	sw	$t4, ANGLE
	li	$t4, 1
	sw	$t4, ANGLE_CONTROL
	li	$t4, 1
	sw	$t4, VELOCITY
	j	mto_go_left
mto_go_right:
	lw	$t4, BOT_X
	beq	$t4, $t2, mto_go_vert_choice
	li	$t4, 0
	sw	$t4, ANGLE
	li	$t4, 1
	sw	$t4, ANGLE_CONTROL
	li	$t4, 1
	sw	$t4, VELOCITY
	j	mto_go_right
mto_go_vert_choice:
	blt	$t3, $t5, mto_go_up
	j	mto_go_down

mto_go_up:
	lw	$t5, BOT_Y
	beq	$t5, $t3, mto_go_end
	li	$t4, 270
	sw	$t4, ANGLE
	li	$t4, 1
	sw	$t4, ANGLE_CONTROL
	li	$t4, 1
	sw	$t4, VELOCITY
	j	mto_go_up
mto_go_down:
	lw	$t5, BOT_Y
	beq	$t5, $t3, mto_go_end
	li	$t4, 90
	sw	$t4, ANGLE
	li	$t4, 1
	sw	$t4, ANGLE_CONTROL
	li	$t4, 1
	sw	$t4, VELOCITY
	j	mto_go_down

mto_go_end:
	li	$t4, 0
	sw	$t4, VELOCITY
	li	$t1, 4
#	sw	$t1, FIELD_STRENGTH
	la	$t7, planet_info
	sw	$t7, PLANETS_REQUEST
	lw	$t8, 0($t7)
	lw	$t9, 4($t7)
	li	$t6, 0
	li	$t0, 1
go_end_loop:
	bne	$t6, $0, change_skip
	li	$t6, 1
	li	$t1, 5
	sw	$t1, FIELD_STRENGTH
change_skip:
	la	$t7, planet_info
	sw	$t7, PLANETS_REQUEST
	lw	$t8, 0($t7)
	lw	$t9, 4($t7)

	#	lw	$t2, BOT_X
	#	lw	$t3, BOT_Y
	#	bne	$t2, $t8, change_skip
	#	bne	$t3, $t9, change_skip
	#	li	$t6, 0
	#	li	$t1, 0
	#	sw	$t1, FIELD_STRENGTH
	#	j	go_end_loop



	move	$a0, $t8		# p1_x
	lw	$t2, BOT_X		# b_x
	sub	$a0, $a0, $t2
	move	$a1, $t9
	lw	$t2, BOT_Y
	sub	$a1, $a1, $t2
	lw	$t3, 12($t7)

	jal	euclidean_dist
	move	$t2, $v0		# dist between p1 and bot

	li	$t4, 2
	div	$t3, $t4
	mflo	$t3
	mul	$t3, $t3, 2
	beq	$t0, $0, next_con
	blt	$t2, $t3, in_sphere
	j	go_end_loop

end:
	li	$t1, 0
	sw	$t1, FIELD_STRENGTH
	j	infinite

in_sphere:
	li	$t7, 0
	li	$t5, 0
	li	$t6, 0
	li	$t8, 0
	li	$t9, 0
	sub	$sp, 12
	sw	$t7, 8($sp)
	sw	$t8, 0($sp)
	sw	$t9, 4($sp)

in_sphere_loop:
	lw	$t7, 8($sp)
	lw	$t8, 0($sp)
	lw	$t9, 4($sp)
	
	
	lw	$t7, 8($sp)
	beq	$t7, $0, isl_c2
isl_c1:
	lw	$t5, BOT_X
	lw	$t6, BOT_Y
	li	$t7, 0

	lw	$t8, 0($sp)
	lw	$t9, 4($sp)

	sub	$a0, $t5, $t8
	sub	$a1, $t6, $t9

	sw	$t7, 8($sp)
	sw	$t8, 0($sp)
	sw	$t9, 4($sp)
	beq	$a0, $a1, next_con
	j	isl_c_end
isl_c2:
	li	$t7, 1
	lw	$t8, BOT_X
	lw	$t9, BOT_Y
	
	sw	$t7, 8($sp)
	sw	$t8, 0($sp)
	sw	$t9, 4($sp)

	sub	$a0, $t5, $t8
	sub	$a1, $t6, $t9
	beq	$a0, $a1, next_con
	j	isl_c_end

isl_c_end:
	la	$t7, planet_info
	sw	$t7, PLANETS_REQUEST
	lw	$t8, 0($t7)
	lw	$t9, 4($t7)

	move	$a0, $t8		# p1_x
	lw	$t2, BOT_X		# b_x
	sub	$a0, $a0, $t2
	move	$a1, $t9
	lw	$t2, BOT_Y
	sub	$a1, $a1, $t2
	lw	$t3, 12($t7)



	jal	euclidean_dist
	move	$t2, $v0		# dist between p1 and bot

	li	$t4, 2
	div	$t3, $t4
	mflo	$t3
	mul	$t3, $t3, 2

	bgt	$t2, $t3, outside
	j	in_sphere_loop
outside:
	li	$t0, 0
	j	go_end_loop

next_con:
	bge	$t2, $t3, go_end_loop
	li	$t1, 0
	add	$sp, 12
	sw	$t1, FIELD_STRENGTH
	j	main
	
move_to_planet:
mtp_loop:
	#	la	$t1, planet_info
	#	sw	$t1, PLANETS_REQUEST
	#	lw	$t2, 0($t1)		# p1_x\
	#	lw	$t3, 4($t1)
	
	
	lw	$t4, BOT_X		# b_x
	lw	$t5, BOT_Y
	beq	$t2, $t4, mtp_loop
	beq	$t3, $t5, mtp_loop

	blt	$t2, $t4, mtp_right_check
mtp_left_check:
	blt	$t3, $t5, mtp_down_left
	j	mtp_up_left
mtp_right_check:
	blt	$t3, $t5, mtp_down_right
	j	mtp_up_right
mtp_up_left:
	sub	$a0, $t3, $t5
	sub	$a1, $t2, $t4
	sub	$sp, 8
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	jal	sb_arctan
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	add	$sp, 8
	li	$t6, 90
	sub	$t6, $t6, $v0
	sw	$t6, ANGLE
	li	$t6, 1
	sw	$t6, ANGLE_CONTROL
	li	$t6, 1
	sw	$t6, VELOCITY
	j	mtp_check
mtp_up_right:
	sub	$a0, $t3, $t5
	sub	$a1, $t4, $t2
	sub	$sp, 8	
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	jal	sb_arctan
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	add	$sp, 8
	li	$t6, 90
	add	$t6, $t6, $v0
	sw	$t6, ANGLE
	li	$t6, 1
	sw	$t6, ANGLE_CONTROL
	li	$t6, 1
	sw	$t6, VELOCITY
	j	mtp_check
mtp_down_left:
	sub	$a1, $t5, $t3
	sub	$a0, $t2, $t4
	sub	$sp, 8	
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	jal	sb_arctan
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	add	$sp, 8
	li	$t6, 0
	sub	$t6, $t6, $v0
	sw	$t6, ANGLE
	li	$t6, 1
	sw	$t6, ANGLE_CONTROL
	li	$t6, 1
	sw	$t6, VELOCITY
	j	mtp_check
mtp_down_right:
	sub	$a0, $t5, $t3
	sub	$a1, $t4, $t2
	sub	$sp, 8	
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	jal	sb_arctan
	sw	$t0, 0($sp)
	sw	$t1, 4($sp)
	add	$sp, 8
	li	$t6, 180
	add	$t6, $t6, $v0
	sw	$t6, ANGLE
	li	$t6, 1
	sw	$t6, ANGLE_CONTROL
	li	$t6, 1
	sw	$t6, VELOCITY
	j	mtp_check



euclidean_dist:
	mul	$a0, $a0, $a0	# x^2
	mul	$a1, $a1, $a1	# y^2
	add	$v0, $a0, $a1	# x^2 + y^2
	mtc1	$v0, $f0
	cvt.s.w	$f0, $f0	# float(x^2 + y^2)
	sqrt.s	$f0, $f0	# sqrt(x^2 + y^2)
	cvt.w.s	$f0, $f0	# int(sqrt(...))
	mfc1	$v0, $f0
	jr	$ra

	# -----------------------------------------------------------------------
# sb_arctan - computes the arctangent of y / x
# $a0 - x
# $a1 - y
# returns the arctangent
# -----------------------------------------------------------------------

sb_arctan:
	li	$v0, 0		# angle = 0;

	abs	$t0, $a0	# get absolute values
	abs	$t1, $a1
	ble	$t1, $t0, no_TURN_90	  

	## if (abs(y) > abs(x)) { rotate 90 degrees }
	move	$t0, $a1	# int temp = y;
	neg	$a1, $a0	# y = -x;      
	move	$a0, $t0	# x = temp;    
	li	$v0, 90		# angle = 90;  

no_TURN_90:
	bgez	$a0, pos_x 	# skip if (x >= 0)

	## if (x < 0) 
	add	$v0, $v0, 180	# angle += 180;

pos_x:
	mtc1	$a0, $f0
	mtc1	$a1, $f1
	cvt.s.w $f0, $f0	# convert from ints to floats
	cvt.s.w $f1, $f1
	
	div.s	$f0, $f1, $f0	# float v = (float) y / (float) x;

	mul.s	$f1, $f0, $f0	# v^^2
	mul.s	$f2, $f1, $f0	# v^^3
	l.s	$f3, three	# load 5.0
	div.s 	$f3, $f2, $f3	# v^^3/3
	sub.s	$f6, $f0, $f3	# v - v^^3/3

	mul.s	$f4, $f1, $f2	# v^^5
	l.s	$f5, five	# load 3.0
	div.s 	$f5, $f4, $f5	# v^^5/5
	add.s	$f6, $f6, $f5	# value = v - v^^3/3 + v^^5/5

	l.s	$f8, PI		# load PI
	div.s	$f6, $f6, $f8	# value / PI
	l.s	$f7, F180	# load 180.0
	mul.s	$f6, $f6, $f7	# 180.0 * value / PI

	cvt.w.s $f6, $f6	# convert "delta" back to integer
	mfc1	$t0, $f6
	add	$v0, $v0, $t0	# angle += delta

	jr 	$ra


.kdata
chunkIH: .space 24
non_intrpt_str:		.asciiz "Non-interrupt exception.\n"
unhandled_str:		.asciiz "Unhandled interrupt.\n"

.ktext 0x80000180
interrupt_handler:
.set noat
	move	$k1, $at
.set at
	la	$k0, chunkIH
	sw	$a0, 0($k0)
	sw	$a1, 4($k0)
	sw	$t0, 8($k0)
	sw	$t1, 12($k0)
	sw	$t2, 16($k0)
	sw	$v0, 20($k0)

	mfc0	$k0, $13
	srl	$a0, $k0, 2
	and	$a0, $a0, 0xf
	bne	$a0, 0, non_intrpt

interrupt_dispatch:			# Interrupt
	mfc0	$k0, $13
	beq	$k0, $0, done

	and	$a0, $k0, SCAN_MASK	# is there a scan interrupt?
	bne	$a0, 0, scan_interrupt

	li	$v0, 4
	la	$a0, unhandled_str
	syscall
	j	done



scan_interrupt:
#	mul	$t1, $t1, 4
#	add	$t2, $t2, $t1
#	lw	$t2, 0($t2)		# trying to read from the array buggy
#	if1:
#	ble	$t2, $t6, end_if1
#	move	$t5, $t1
#	move	$t6, $t2
#end_if1:
	lw	$t0, scan_occurred
	li	$t0, 1
	sw	$t0, scan_occurred
	sw	$a1, SCAN_ACKNOWLEDGE
	j	interrupt_dispatch



non_intrpt:
	li	$t0, 4			# can be buggy
	la	$a0, non_intrpt_str
	syscall
	j	done

done:					# Will it actually return back to the place where interrupt incurs? 
	la	$k0, chunkIH
	lw	$a0, 0($k0)
	lw	$a1, 4($k0)
	lw	$t0, 8($k0)
	lw	$t1, 12($k0)
	lw	$t2, 16($k0)
	lw	$v0, 20($k0)

.set noat
	move	$a1, $k1
.set at
	eret



