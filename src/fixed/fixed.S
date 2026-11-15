# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    # t0 is current loop count, sw after loop ends
    # t1 is carry
    # while (b)
    li t0, 0
    beqz a1, op1_loop_end
op1_loop:
    # c = (a & b) << 1;
    and t1, a0, a1
    slli t1, t1, 1
    # a = a^b
    xor a0, a0, a1
    # b=c
    mv a1, t1
    addi t0, t0, 1
    bnez a1, op1_loop
op1_loop_end:
    sw t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    # ((a ^ b) >> 1) + (a & b);
    and t0, a0, a1
    xor a0, a0, a1
    srli a0, a0, 1
    add a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # t0: loop_count, t5: temp, t6: 1
    # a0: a, a1: b

    # res = 0: t1 is high 32, t2 is low 32
    li t1, 0
    li t2, 0
    # cur = a: t3 is high 32, t4 is low 32
    srai t3, a0, 31 # sign bits
    mv t4, a0

    li t0, 32 # loop count
    li t6, 1

    beqz t0, q_mul_loop_end
q_mul_loop:
    andi t5, a1, 1
    # not adding if bit is 0
    beqz t5, q_mul_loop_no_add
    # jump to add if t0!=1 (not last loop)
    bne t0, t6, q_mul_loop_add
q_mul_loop_minus:
    # res -= cur;
    sltu t5, t2, t4 # t5 = need borrow
    # high bits
    sub t1, t1, t3
    sub t1, t1, t5
    # low bits
    # TODO: same low bits whether borrow or not because they have the same remainder
    sub t2, t2, t4
    j q_mul_loop_no_add
q_mul_loop_add:
    # res+=cur
    # low bits
    add t2, t2, t4
    sltu t5, t2, t4 # t5 = carry for high bits
    # high bits = res+cur+carry
    add t1, t1, t3
    add t1, t1, t5
q_mul_loop_no_add:
    addi t0, t0, -1
    srli a1, a1, 1 # b>>i for next loop
    # cur <<= 1;
    # cur_high=(cur_high<<1)|(cur_low>>31)
    slli t3, t3, 1
    srli t5, t4, 31
    or t3, t3, t5
    # cur_low<<=1
    slli t4, t4, 1
    bnez t0, q_mul_loop
q_mul_loop_end:
    # res += (1u << (20 - 1))
    slli t6, t6, 19 # since t6=1
    add t2, t2, t6
    sltu t5, t2, t6 # t5 = carry
    add t1, t1, t5
    # res >>= 20;
    srli t2, t2, 20
    slli t1, t1, 12
    or a0, t1, t2
    ret
    .size   q_mul_asm, .-q_mul_asm
