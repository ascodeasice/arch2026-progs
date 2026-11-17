# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
#
# Ported from Homework 1 (~/code/minirubik/cube.S); the move tables and
# pattern databases are in rubik_moves.S.

        .data
# move m turns face m / 3 by m % 3 + 1 quarter turns, 4 bytes per name
names:
        .byte   82, 32, 0, 0        # "R "
        .byte   82, 50, 32, 0       # "R2 "
        .byte   82, 39, 32, 0       # "R' "
        .byte   66, 32, 0, 0        # "B "
        .byte   66, 50, 32, 0       # "B2 "
        .byte   66, 39, 32, 0       # "B' "
        .byte   68, 32, 0, 0        # "D "
        .byte   68, 50, 32, 0       # "D2 "
        .byte   68, 39, 32, 0       # "D' "

# (6 - i)! * 4 and 3^(5 - i) * 4, so ranks come out as byte offsets
fact4:  .word   2880, 480, 96, 24, 8, 4, 0
pow4:   .word   972, 324, 108, 36, 12, 4

cube_p: .byte   0, 0, 0, 0, 0, 0, 0, 7  # cubie at each position, 7 is fixed
cube_o: .zero   8                   # its orientation

moves:  .zero   12                  # solution as move codes
frames: .zero   192                 # saved levels, 16 bytes each
# where each of the nine moves resumes, indexed by move code; Ripes cannot
# put a text label in .word, so solve fills it in
resume: .zero   36

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
# Entry, with the pseudo code of each step above its instructions.
#
#   stack frame, 64 bytes so sp stays 16-byte aligned:
#     0(sp) ra, 4(sp)..48(sp) s0..s11, 52(sp) out, 56(sp) cap
#   parse and solve change every t, a and s1..s11 register, so out and cap
#   must live on the stack, not in a1/a2
#
#   sp -= 64; save ra, s0..s11, out (a1), cap (a2)
        addi sp, sp, -64
        sw ra, 0(sp)
        sw s0, 4(sp)
        sw s1, 8(sp)
        sw s2, 12(sp)
        sw s3, 16(sp)
        sw s4, 20(sp)
        sw s5, 24(sp)
        sw s6, 28(sp)
        sw s7, 32(sp)
        sw s8, 36(sp)
        sw s9, 40(sp)
        sw s10, 44(sp)
        sw s11, 48(sp)
        sw a1, 52(sp)
        sw a2, 56(sp)
#   s0 = state (a0)                     # parse reads the digits at s0
        mv s0, a0
#   call parse                          # a0 = p * 4, a1 = o * 4, or a0 = -1
        jal ra, parse
# if a0 < 0: result = -1, goto done   # invalid, out untouched
# a0 is already -1 after parse
        bltz a0, done
#   if cap == 0: result = -2, goto done # no room even for the NUL
        lw t1, 56(sp)           # cap: parse changed a2
        beqz t1, no_room
#   call solve                          # a0 = length, moves[0..length-1]
        jal ra, solve
#   a0 = len from here on, it is also the result
        lw t0, 52(sp)           # out
        lw t1, 56(sp)           # cap: solve changed every a register
        li t2, 0                # j, bytes written to out
        li t3, 0                # i, the move being written
        la a1, moves
        la a2, names
        li a3, 32               # ' '
        addi a4, a0, -1         # len - 1, the last move gets no space
        blez a0, output_end     # solved cube (or -1): only the NUL
output_loop:
#       name = names + moves[i] * 4     # "R2 " padded with 0, see above
        add t6, a1, t3
        lbu t4, 0(t6)           # moves[i], 0..8
        slli t4, t4, 2
        add t4, a2, t4          # name
name_loop:
#       for each byte c of name until c == ' ':
        lbu t5, 0(t4)           # c
        beq t5, a3, name_end
#           if j + 1 >= cap: out[0] = 0; result = -2; goto done
        addi t6, t2, 1
        bgeu t6, t1, overflow
#           out[j] = c; j += 1
        add t6, t0, t2
        sb t5, 0(t6)
        addi t2, t2, 1
        addi t4, t4, 1
        j name_loop
name_end:
#       if i < len - 1: out[j] = ' '; j += 1
        beq t3, a4, next_move
        add t6, t0, t2
        sb a3, 0(t6)            # fits: the check above left room
        addi t2, t2, 1
next_move:
        addi t3, t3, 1
        bne t3, a0, output_loop
output_end:
#   out[j] = 0                          # NUL, also "" for the solved cube
        add t6, t0, t2
        sb zero, 0(t6)
        j done                  # result = len, already in a0
overflow:
        sb zero, 0(t0)          # out[0] = 0, then return -2
no_room:
        li a0, -2
done:
        # restore ra, s0..s11
        # a0 = result(a0 is already result); restore ra, s0..s11; sp += 64; ret
        lw ra, 0(sp)
        lw s0, 4(sp)
        lw s1, 8(sp)
        lw s2, 12(sp)
        lw s3, 16(sp)
        lw s4, 20(sp)
        lw s5, 24(sp)
        lw s6, 28(sp)
        lw s7, 32(sp)
        lw s8, 36(sp)
        lw s9, 40(sp)
        lw s10, 44(sp)
        lw s11, 48(sp)
        addi sp, sp, 64
        ret
#
# Same logic as rubik_solve in rubik.c (the -1, -2 and output part).

# parse the case at s0 into cube_p/cube_o and return the ranks as byte
# offsets: a0 = p * 4, a1 = o * 4, or a0 = -1 if the state is invalid
parse:
        la      t0, cube_p
        la      t1, cube_o
        li      t2, 0               # i
        li      t3, 0               # seen cubies, one bit each
        li      t4, 0               # orientation sum
        li      t6, 7
parse_loop:
        add     a2, s0, t2
        lbu     a3, 0(a2)           # cubie digit
        lbu     a4, 7(a2)           # orientation digit
        addi    a3, a3, -49
        addi    a4, a4, -49
        bgeu    a3, t6, invalid     # unsigned compare also catches < '1'
        li      a5, 3
        bgeu    a4, a5, invalid
        li      a5, 1
        sll     a5, a5, a3
        and     a6, t3, a5
        bnez    a6, invalid         # cubie seen twice
        or      t3, t3, a5
        add     t4, t4, a4
        add     a2, t0, t2
        sb      a3, 0(a2)
        add     a2, t1, t2
        sb      a4, 0(a2)
        addi    t2, t2, 1
        bne     t2, t6, parse_loop
        lbu     a3, 14(s0)
        bnez    a3, invalid         # longer than 14 digits
mod3:
        addi    t4, t4, -3          # sum <= 14, subtract until negative
        bgez    t4, mod3
        addi    t4, t4, 3
        bnez    t4, invalid
        # Lehmer rank: add (6 - i)! * 4 for every later cubie that is smaller
        li      a0, 0
        la      a5, fact4
        li      t2, 0
rank_i:
        add     a2, t0, t2
        lbu     a3, 0(a2)
        lw      a6, 0(a5)
        addi    t5, t2, 1
rank_j:
        beq     t5, t6, rank_next
        add     a2, t0, t5
        lbu     a4, 0(a2)
        bgeu    a4, a3, rank_skip
        add     a0, a0, a6
rank_skip:
        addi    t5, t5, 1
        j       rank_j
rank_next:
        addi    a5, a5, 4
        addi    t2, t2, 1
        bne     t2, t6, rank_i
        # base-3 rank of the first six orientations, digit 2 adds twice
        li      a1, 0
        la      a5, pow4
        li      t2, 0
orient_rank:
        add     a2, t1, t2
        lbu     a3, 0(a2)
        lw      a6, 0(a5)
orient_add:
        beqz    a3, orient_next
        add     a1, a1, a6
        addi    a3, a3, -1
        j       orient_add
orient_next:
        addi    a5, a5, 4
        addi    t2, t2, 1
        addi    a3, t2, -6
        bnez    a3, orient_rank
        ret
invalid:
        li      a0, -1
        ret

# IDA*: a0 = p * 4, a1 = o * 4 -> a0 = length and moves filled, or -1
solve:
        or      t0, a0, a1
        bnez    t0, unsolved
        li      a0, 0
        ret
unsolved:
        # bound starts at h(root) = max of the two pattern databases
        srli    t0, a0, 2
        la      t1, pdb_perm
        add     t1, t1, t0
        lbu     a2, 0(t1)
        srli    t0, a1, 2
        la      t1, pdb_orient
        add     t1, t1, t0
        lbu     t0, 0(t1)
        bge     a2, t0, bound_set
        mv      a2, t0
bound_set:
        # one base register per face and table, so every turn is fixed code
        la      s3, move_perm
        li      t0, 20160           # one face of move_perm in bytes
        add     s4, s3, t0
        add     s10, s4, t0
        la      s11, move_orient
        li      t0, 2916            # one face of move_orient
        add     a4, s11, t0
        add     a5, a4, t0
        la      t1, resume
        la      t0, f0t2
        sw      t0, 0(t1)
        la      t0, f0t3
        sw      t0, 4(t1)
        la      t0, f0end
        sw      t0, 8(t1)
        la      t0, f1t2
        sw      t0, 12(t1)
        la      t0, f1t3
        sw      t0, 16(t1)
        la      t0, f1end
        sw      t0, 20(t1)
        la      t0, f2t2
        sw      t0, 24(t1)
        la      t0, f2t3
        sw      t0, 28(t1)
        la      t0, f2end
        sw      t0, 32(t1)
        li      t4, 1
        li      t5, 2
        la      a3, frames
iteration:
        # one depth-first pass, root at depth 0 with no previous face
        mv      s8, a0
        mv      s9, a1
        li      s5, 3
        addi    s6, a2, -1          # moves left after a child of the root
        mv      s7, a3
        j       node
descend0:
        li      a6, 0
        j       descend
descend1:
        li      a6, 1
        j       descend
descend2:
        li      a6, 2
descend:
        beqz    s6, found           # h = 0 only at solved
        # save this level, 16 bytes, the child becomes the node
        sw      t6, 0(s7)
        sw      s8, 4(s7)
        sw      s9, 8(s7)
        sw      s5, 12(s7)
        addi    s7, s7, 16
        mv      s8, s1
        mv      s9, s2
        mv      s5, a6
        addi    s6, s6, -1
node:
        # never turn the same face twice: skip the face in s5
        beqz    s5, face1
face0:
        mv      s1, s8
        mv      s2, s9
f0t1:
        add     t0, s3, s1
        lhu     s1, 0(t0)           # next permutation offset
        lbu     t1, 2(t0)           # its pattern database value
        add     t2, s11, s2
        lhu     s2, 0(t2)
        lbu     t3, 2(t2)
        blt     s6, t1, f0t2       # h > moves left
        blt     s6, t3, f0t2
        jal     t6, descend0      # t6 is where this level resumes
f0t2:
        add     t0, s3, s1
        lhu     s1, 0(t0)           # next permutation offset
        lbu     t1, 2(t0)           # its pattern database value
        add     t2, s11, s2
        lhu     s2, 0(t2)
        lbu     t3, 2(t2)
        blt     s6, t1, f0t3       # h > moves left
        blt     s6, t3, f0t3
        jal     t6, descend0      # t6 is where this level resumes
f0t3:
        # last turn of the face: nothing reuses the ranks if it is pruned,
        # so test first and load them only for a child that is entered
        add     t0, s3, s1
        lbu     t1, 2(t0)
        blt     s6, t1, f0end       # h > moves left
        add     t2, s11, s2
        lbu     t3, 2(t2)
        blt     s6, t3, f0end
        lhu     s1, 0(t0)
        lhu     s2, 0(t2)
        jal     t6, descend0      # t6 is where this level resumes
f0end:
        beq     s5, t4, face2
face1:
        mv      s1, s8
        mv      s2, s9
f1t1:
        add     t0, s4, s1
        lhu     s1, 0(t0)           # next permutation offset
        lbu     t1, 2(t0)           # its pattern database value
        add     t2, a4, s2
        lhu     s2, 0(t2)
        lbu     t3, 2(t2)
        blt     s6, t1, f1t2       # h > moves left
        blt     s6, t3, f1t2
        jal     t6, descend1      # t6 is where this level resumes
f1t2:
        add     t0, s4, s1
        lhu     s1, 0(t0)           # next permutation offset
        lbu     t1, 2(t0)           # its pattern database value
        add     t2, a4, s2
        lhu     s2, 0(t2)
        lbu     t3, 2(t2)
        blt     s6, t1, f1t3       # h > moves left
        blt     s6, t3, f1t3
        jal     t6, descend1      # t6 is where this level resumes
f1t3:
        # last turn of the face: nothing reuses the ranks if it is pruned,
        # so test first and load them only for a child that is entered
        add     t0, s4, s1
        lbu     t1, 2(t0)
        blt     s6, t1, f1end       # h > moves left
        add     t2, a4, s2
        lbu     t3, 2(t2)
        blt     s6, t3, f1end
        lhu     s1, 0(t0)
        lhu     s2, 0(t2)
        jal     t6, descend1      # t6 is where this level resumes
f1end:
        beq     s5, t5, ascend
face2:
        mv      s1, s8
        mv      s2, s9
f2t1:
        add     t0, s10, s1
        lhu     s1, 0(t0)           # next permutation offset
        lbu     t1, 2(t0)           # its pattern database value
        add     t2, a5, s2
        lhu     s2, 0(t2)
        lbu     t3, 2(t2)
        blt     s6, t1, f2t2       # h > moves left
        blt     s6, t3, f2t2
        jal     t6, descend2      # t6 is where this level resumes
f2t2:
        add     t0, s10, s1
        lhu     s1, 0(t0)           # next permutation offset
        lbu     t1, 2(t0)           # its pattern database value
        add     t2, a5, s2
        lhu     s2, 0(t2)
        lbu     t3, 2(t2)
        blt     s6, t1, f2t3       # h > moves left
        blt     s6, t3, f2t3
        jal     t6, descend2      # t6 is where this level resumes
f2t3:
        # last turn of the face: nothing reuses the ranks if it is pruned,
        # so test first and load them only for a child that is entered
        add     t0, s10, s1
        lbu     t1, 2(t0)
        blt     s6, t1, f2end       # h > moves left
        add     t2, a5, s2
        lbu     t3, 2(t2)
        blt     s6, t3, f2end
        lhu     s1, 0(t0)
        lhu     s2, 0(t2)
        jal     t6, descend2      # t6 is where this level resumes
f2end:
ascend:
        # every move tried: back up one level, the child was s8/s9
        beq     s7, a3, deeper
        addi    s7, s7, -16
        mv      s1, s8
        mv      s2, s9
        lw      t6, 0(s7)
        lw      s8, 4(s7)
        lw      s9, 8(s7)
        lw      s5, 12(s7)
        addi    s6, s6, 1
        jr      t6
deeper:
        addi    a2, a2, 1
        li      t0, 12
        bne     a2, t0, iteration
        li      a0, -1
        ret
found:
        # every saved resume address names a move, look each one up
        sw      t6, 0(s7)
        la      t0, moves
        mv      t1, a3
copy:
        lw      t2, 0(t1)
        la      t3, resume
        li      a6, 0
find:
        lw      a7, 0(t3)
        beq     a7, t2, code_found
        addi    t3, t3, 4
        addi    a6, a6, 1
        j       find
code_found:
        sb      a6, 0(t0)
        addi    t0, t0, 1
        addi    t1, t1, 16
        bgeu    s7, t1, copy
        mv      a0, a2
        ret

    .size   rubik_solve_asm, .-rubik_solve_asm
