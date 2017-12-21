.data

# syscall constant
PRINT_STRING	    = 4
SBRK		    = 9

# sector constants
SECTOR_HALF	    = 18
SECTOR_SIZE	    = 37
SECTORS_PER_ROW	    = 8
NUM_SECTORS	    = 64

# movement memory-mapped I/O
VELOCITY            = 0xffff0010
ANGLE               = 0xffff0014
ANGLE_CONTROL       = 0xffff0018


# strategy constants
# subject to change based on actual results
BOT_FIELD_STRENGTH  = 8
MTP_VELOCITY	    = 4

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

# puzzle interface locations 
SPIMBOT_PUZZLE_REQUEST 		= 0xffff1000 
SPIMBOT_SOLVE_REQUEST 		= 0xffff1004 
SPIMBOT_LEXICON_REQUEST 	= 0xffff1008


# I/O used in competitive scenario 
INTERFERENCE_MASK 	= 0x8000 
INTERFERENCE_ACK 	= 0xffff1304 
SPACESHIP_FIELD_CNT  	= 0xffff110c 

# strategy constants

# there's nothing special about these numbers
# (except that they're all powers of two) ...
# they were just derived from trial and error

DUST_FIELD_STRENGTH = 8
CHASE_VELOCITY      = 4
DUST_WAIT_CYCLES    = 8192
CHASE_ITERATIONS    = 2048

# global varibles 

scan_done:
	.word 0

energy_occurred:
	.word 0

interference_occurred:
	.word 0

.align 2
dust:
	.space 256

.align 2
energy_data:
	.space 4

.align 2
planets:
	.space 32

.align 2
puzzle_struct:
	.space 4104

.align 2
lexicon_struct:
	.space 4010

.align 2
solution_struct:
	.space 808

words:
	.space 800

num_words:
	.word 0

.align 2
curr_dust:
	.space 1024



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


# check_energy ----------------------------------------------------------------------
# check energy in some functions
# $v0: 0 no need for more, 1 need to gain more
check_energy:
	##	la	$a0, energy_data
	##	sw	$0, energy_occurred
	
	lw	$t1, ENERGY

	## ce_wait:	
	## 	lw	$t1, energy_occurred
	## 	beq	$t1, 0, ce_wait
	## 
	## 	lw	$t1, 0($a0)
 	li	$t2, 100

	ble	$t1, $t2, ce_result1

ce_result0:
	li	$v0, 0
	jr	$ra

ce_result1:
	li	$v0, 1
	jr	$ra

# gain_energy -----------------------------------------------------------------------
# solve puzzle to gain more energy
gain_energy:
	sub	$sp, $sp, 12		# may be different.
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	
	la	$t0, solution_struct
	li	$t1, 0
	sw	$t1, 0($t0)
	
	la	$s0, lexicon_struct
	sw	$s0, SPIMBOT_LEXICON_REQUEST

	la	$s1, puzzle_struct
	sw	$s1, SPIMBOT_PUZZLE_REQUEST

	la	$a0, 4($s0)		# CHECK! lw or other inst?
	lw	$a1, 0($s0)
	jal	find_words

					# either need to save more frequently to
					# gain instant energy, or to improve
					# puzzle solving efficiency
	la	$t1, solution_struct
	sw	$t1, SPIMBOT_SOLVE_REQUEST
	
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	
	add	$sp, $sp, 12
	jr	$ra

## char
## get_character(int i, int j) {
##     return puzzle[i * num_columns + j];
## }

get_character:
	la	$t0, puzzle_struct
	lw	$t0, 4($t0)
	mul	$t0, $a0, $t0
	add	$t0, $t0, $a1
	la	$t1, puzzle_struct
	add	$t1, $t1, 8
	add	$t1, $t1, $t0
	lbu	$v0, 0($t1)
	jr	$ra


## int
## horiz_strncmp(const char* word, int start, int end, int word_length) {
##     if (word_length > end - start + 1)
##         return 0;
##
##     int word_iter = 0;
## 
##     while (start <= end) {
##         if (puzzle[start] != word[word_iter]) {
##             return 0;
##         }
## 
##         if (word[word_iter + 1] == '\0') {
##             return start;
##         }
## 
##         start++;
##         word_iter++;
##     }
##     
##     return 0;
## }

horiz_strncmp:
	sub	$t0, $a2, $a1		# end - start
	add	$t0, $t0, 1             # + 1
	
	ble	$a3, $t0, green_light
	
	move	$v0, $0
	jr	$ra
	
green_light:
	li	$t0, 0			# word_iter = 0
	la	$t1, puzzle_struct
	add	$t1, $t1, 8

hs_while:
	bgt	$a1, $a2, hs_end	# !(start <= end)

	add	$t2, $t1, $a1		# &puzzle[start]
	lbu	$t2, 0($t2)		# puzzle[start]
	add	$t3, $a0, $t0		# &word[word_iter]
	lbu	$t4, 0($t3)		# word[word_iter]
	beq	$t2, $t4, hs_same	# !(puzzle[start] != word[word_iter])
	li	$v0, 0			# return 0
	jr	$ra

hs_same:
	lbu	$t4, 1($t3)		# word[word_iter + 1]
	bne	$t4, 0, hs_next		# !(word[word_iter + 1] == '\0')
	move	$v0, $a1		# return start
	jr	$ra

hs_next:
	add	$a1, $a1, 1		# start++
	add	$t0, $t0, 1		# word_iter++
	j	hs_while

hs_end:
	li	$v0, 0			# return 0
	jr	$ra

## int
## horiz_strncmp_back(const char* word, int start, int end, int word_length)
## {
##     if (word_length > end - start + 1)
##         return 0;
##
##     int word_iter = 0;
##
##     int tmp_end = end;
##     while (start >= tmp_end)
##     {
##         if (puzzle[tmp_end] != word[word_iter])
##             return 0;
## 
##         if (word[word_iter + 1] == '\0')
##             return tmp_end;
## 
##         tmp_end--;
##         word_iter++;
##         
##     }
##  	
##     return 0;
## }
##
## $a0: word array
## $a1: start, should remain unchanged
## $a2: end, will be assigned to $t2

horiz_strncmp_back:
	sub	$t0, $a2, $a1		# end - start
	add	$t0, $t0, 1             # + 1
	ble	$a3, $t0, green_lightb
	
	move	$v0, $0
	jr	$ra
	
green_lightb:
	li	$t0, 0			# word_iter = 0
	la	$t1, puzzle_struct
	add	$t1, $t1, 8

hsb_while:
	blt	$a1, $a2, hsb_end	# !(start >= end)

	add	$t2, $t1, $a2		# &puzzle[start]
	lbu	$t2, 0($t2)		# puzzle[start]
	add	$t3, $a0, $t0		# &word[word_iter]
	lbu	$t4, 0($t3)		# word[word_iter]
	beq	$t2, $t4, hsb_same	# !(puzzle[start] != word[word_iter])
	li	$v0, 0			# return 0
	jr	$ra

hsb_same:
	lbu	$t4, 1($t3)		# word[word_iter + 1]
	bne	$t4, 0, hsb_next		# !(word[word_iter + 1] == '\0')
	move	$v0, $a2		# return start
	jr	$ra

hsb_next:
	add	$a2, $a2, 1		# start++
	add	$t0, $t0, 1		# word_iter++
	j	hsb_while

hsb_end:
	li	$v0, 0			# return 0
	jr	$ra
	jr	$ra

## int
## vert_strncmp(const char* word, int start_i, int j) {
##     int word_iter = 0;
## 
##     for (int i = start_i; i < num_rows; i++, word_iter++) {
##         if (get_character(i, j) != word[word_iter]) {
##             return 0;
##         }
## 
##         if (word[word_iter + 1] == '\0') {
##             // return ending address within array
##             return i * num_columns + j;
##         }
##     }
## 
##     return 0;
## }

vert_strncmp:
	sub	$sp, $sp, 24
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)

	move	$s0, $a0		# word
	move	$s1, $a1		# i = start_i
	move	$s2, $a2		# j
	li	$s3, 0			# word_iter
	la	$s4, puzzle_struct
	lw	$s4, 0($s4)

vs_for:
	bge	$s1, $s4, vs_nope	# !(i < num_rows)

	move	$a0, $s1
	move	$a1, $s2
	jal	get_character		# get_character(i, j)
	add	$t0, $s0, $s3		# &word[word_iter]
	lbu	$t1, 0($t0)		# word[word_iter]
	bne	$v0, $t1, vs_nope

	lbu	$t1, 1($t0)		# word[word_iter + 1]
	bne	$t1, 0, vs_next
	la	$v0, puzzle_struct
	lw	$v0, 4($v0)
	mul	$v0, $s1, $v0		# i * num_columns
	add	$v0, $v0, $s2		# i * num_columns + j
	j	vs_return

vs_next:
	add	$s1, $s1, 1		# i++
	add	$s3, $s3, 1		# word_iter++
	j	vs_for

vs_nope:
	li	$v0, 0			# return 0 (data flow)

vs_return:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	add	$sp, $sp, 24
	jr	$ra

## int
## vert_strcmp_back(const char* word, int end_i, int j)
## {
##     int word_iter = 0;
## 
##     for (int i = end_i; i >= 0; i--, word_iter++)
##     {
##         if (get_character(i, j) != word[word_iter])
##             return 0;
## 
##         if (word[word_iter + 1] == '\0')
##         {
##             return i * num_columns + j;
##         }
##     }
## 
##     return 0;
## }
	
vert_strncmp_back:
	sub	$sp, $sp, 24
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)

	move	$s0, $a0		# word
	move	$s1, $a1		# i = end_i
	move	$s2, $a2		# j
	li	$s3, 0			# word_iter
	la	$s4, puzzle_struct
	lw	$s4, 0($s4)

vsb_for:
	blt	$s1, 0, vsb_nope	# !(i >= 0)

	move	$a0, $s1
	move	$a1, $s2
	jal	get_character		# get_character(i, j)
	add	$t0, $s0, $s3		# &word[word_iter]
	lbu	$t1, 0($t0)		# word[word_iter]
	bne	$v0, $t1, vsb_nope

	lbu	$t1, 1($t0)		# word[word_iter + 1]
	bne	$t1, 0, vsb_next
	la	$v0, puzzle_struct
	lw	$v0, 4($v0)
	mul	$v0, $s1, $v0		# i * num_columns
	add	$v0, $v0, $s2		# i * num_columns + j
	j	vsb_return

vsb_next:
	sub	$s1, $s1, 1		# i--
	add	$s3, $s3, 1		# word_iter++
	j	vsb_for

vsb_nope:
	li	$v0, 0			# return 0 (data flow)

vsb_return:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	add	$sp, $sp, 24
	jr	$ra
	jr	$ra


## int strlen(const char *word) {
##     int i = 0;
## 
##     while (word[i] != '\0') {
##         i++;
##     }
##     
##     return i;
##}

strlen:
	li	$v0, 0			# i = 0

strl_while:
	add	$t1, $a0, $v0		# &word[i]
	lbu	$t2, 0($t1)		# word[i]
	beq	$t2, 0, strl_end	# word[i] != '\0'

strl_next:
	add	$v0, $v0, 1		# i++
	j	strl_while

strl_end:
	jr	$ra

## void find_words(const char** dictionary, int dictionary_size) {
##     for (int k = 0; k < dictionary_size; k++) {
##         const char* word = dictionary[k];
##         int word_length = strlen(word);
##
##         for (int i = 0; i < num_rows; i++) {
##             for (int j = 0; j < num_columns; j++) {
##                 int start = i * num_columns + j;
##                 int end = (i + 1) * num_columns - 1;
##                
##                 int word_end = horiz_strncmp(word, start, end, word_length);
##                 if (word_end > 0) {
##                     record_word(word, start, word_end);
##                 }
##
##                 int word_start = horiz_strncmp_back(word, start, end, word_length);
##                 if (word_start > 0) {
##                     record_word(word, word_start, end);
##                 }
## 
##                 word_end = vert_strncmp(word, i, j);
##                 if (word_end > 0) {
##                     record_word(word, start, word_end);
##                 }
## 
##                 word_start = vert_strncmp_back(word, i, j);
##                 if (word_start > 0) {
##                     record_word(word, word_start, end);
##                 }
## 
##             }
##         }
##     }
## }
find_words:
	sub	$sp, $sp, 40
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)
	sw	$s5, 24($sp)
	sw	$s6, 28($sp)
	sw	$s7, 32($sp)
	sw	$s8, 36($sp)

	move	$s0, $a0		# dictionary
	move	$s1, $a1		# dictionary_size
	la	$s2, puzzle_struct
	lw	$s2, 4($s2)
	
	li	$s7, 0			# k = 0

fw_k:
	bge	$s7, $s1, fw_done	# !(k < dictionary_size)
	mul	$t0, $s7, 4		# k * 4
	add	$t0, $s0, $t0		# &dictionary[k]
	lw	$s8, 0($t0)		# word = dictionary[k]
	
	move    $a0, $s8		# pre-compute strlen
	jal     strlen
	move    $t6, $v0		# hack: since no other parts of the codebase use $t6 we treat it as a '$s9'
	
	li	$s3, 0			# i = 0

fw_i:
	la	$t0, puzzle_struct
	lw	$t0, 0($t0)
	bge	$s3, $t0, fw_k_next	# !(i < num_rows)
	li	$s4, 0			# j = 0

fw_j:
	bge	$s4, $s2, fw_i_next	# !(j < num_columns)
	mul	$t0, $s3, $s2		# i * num_columns
	add	$s5, $t0, $s4		# start = i * num_columns + j
	add	$t0, $t0, $s2		# equivalent to (i + 1) * num_columns
	sub	$s6, $t0, 1		# end = (i + 1) * num_columns - 1

fw_horz:
	move	$a0, $s8		# word
	move	$a1, $s5		# start
	move	$a2, $s6		# end
	jal	horiz_strncmp
	ble	$v0, 0, fw_horzb	# !(word_end > 0)
	move	$a0, $s8		# word
	move	$a1, $s5		# start
	move	$a2, $v0		# word_end
	move    $a3, $t6		# word_length
	jal	record_word
	## 	lw	$t1, ENERGY
	## 	li	$t2, 100
	## 	bge	$t1, $t2, fw_done

fw_horzb:
	move	$a0, $s8		# word
	move	$a1, $s5		# start
	move	$a2, $s6		# end
	jal	horiz_strncmp_back
	ble	$v0, 0, fw_vert		# !(word_end > 0)
	move	$a0, $s8		# word
	move	$a1, $s6		# start
	move	$a2, $v0		# word_end
	move    $a3, $t6
	jal	record_word
	## 	lw	$t1, ENERGY
	## 	li	$t2, 100
	## 	bge	$t1, $t2, fw_done

fw_vert:
	move	$a0, $s8		# word
	move	$a1, $s3		# i
	move	$a2, $s4		# j
	jal	vert_strncmp
	ble	$v0, 0, fw_vertb	# !(word_end > 0)
	move	$a0, $s8		# word
	move	$a1, $s5		# start
	move	$a2, $v0		# word_end
	jal	record_word
	## 	lw	$t1, ENERGY
	## 	li	$t2, 100
	## 	bge	$t1, $t2, fw_done


fw_vertb:
	move	$a0, $s8		# word
	move	$a1, $s3		# i
	move	$a2, $s4		# j
	jal	vert_strncmp_back
	ble	$v0, 0, fw_j_next	# !(word_end > 0)
	move	$a0, $s8		# word
	move	$a1, $s5		# end
	move	$a2, $v0		# word_start
	jal	record_word

fw_j_next:
	add	$s4, $s4, 1		# j++
	j	fw_j

fw_i_next:
	add	$s3, $s3, 1		# i++
	j	fw_i

fw_k_next:

	lw	$t1, ENERGY
	li	$t2, 80
	bge	$t1, $t2, fw_done

	add	$s7, $s7, 1		# k++
	j	fw_k

fw_done:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	lw	$s5, 24($sp)
	lw	$s6, 28($sp)
	lw	$s7, 32($sp)
	lw	$s8, 36($sp)
	add	$sp, $sp, 40
	jr	$ra

# record_word
# essentially an int arr that stores the pair of int into words_end
# also calculates and stores the num of words into data seg
# $a0: the word
# $a1: start pos
# $a2: end pos
record_word:
	la	$t0, solution_struct
	lw	$t1, 0($t0)

	mul	$t2, $t1, 8
	add	$t3, $t0, 4
	add	$t3, $t3, $t2
	sw	$a1, 0($t3)
	sw	$a2, 4($t3)

	add	$t1, $t1, 1
	sw	$t1, 0($t0)

	li	$t9, 3
	bne	$t1, $t9, rw_end

	sw	$t0, SPIMBOT_SOLVE_REQUEST
	li	$t1, 0
	sw	$t1, 0($t0)

rw_end:
	jr	$ra
	
# main ------------------------------------------------------------------------------
# your code goes here
# for the interrupt-related portions, you'll want to
# refer closely to example.s - it's probably easiest
# to copy-paste the relevant portions and then modify them
# keep in mind that example.s has bugs, as discussed in section
main:
	sub	$sp, $sp, 4
	sw	$ra, 0($sp)
	sw	$0, VELOCITY

fetch:
	la	$t0, curr_dust
	sw	$t0, SPACESHIP_FIELD_CNT
	
	li	$t0, SCAN_MASK
	#or	$t0, $t0, ENERGY_MASK
	or	$t0, $t0, INTERFERENCE_MASK
	or	$t0, $t0, 1

	mtc0	$t0, $12
	

	# no argument; $v0: sector number
	jal	find_best_sector	
	
	
	# $a0: sector number; $v0: xcoord, $v1: ycoord
	move	$a0, $v0
	jal	get_sector_center	

	# $a0: xcoord, $a1: ycoord; no return val
	move	$a0, $v0
	move	$a1, $v1
	jal	pick_up_dust

        # start to attract dust   open FIELD_STRENGTH      = 0xffff1100

carry:
	jal	chase_planet
	sw	$zero, VELOCITY
	sw	$zero, FIELD_STRENGTH



gain_energy_loop:
	lw	$v0, ENERGY

	li	$t0, 80

	bgt	$v0, $t0, fetch

	jal	gain_energy

	j	gain_energy_loop
	

loop:
	j	loop
	# never reached
	lw	$ra, 0($sp)
	add	$sp, $sp, 4
	jr	$ra

##wait_for_planet:
##	# wait in orbit for friendly planet
##	# when enters planet's hemisphere release dust
##	# check energy level
##	# gain more energy when lower than certain amount
##	jr	$ra

##move_to_orbit:
##	# move the bot to planet orbit
##	# only move when have enough energy
##	jr	$ra


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

	and	$a0, $k0, INTERFERENCE_MASK # is there a interference interrupt?                
	bne	$a0, 0, interference_interrupt

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

interference_interrupt:
	sw	$zero, INTERFERENCE_ACK	# acknowledge interrupt
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

