# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    # a = a0, b = a1
    beqz a0, ret_b
    beqz a1, ret_a

    # t0 = two_count
    # t1 = 1
    # t2 for temp result
    li t0, 0
    li t1, 1
get_two_count:
    # end if a is odd or b is odd
    andi t2, a0, 1
    beq t2, t1, binary_gcd
    andi t2, a1, 1
    beq t2, t1, binary_gcd
    srli a0, a0, 1
    srli a1, a1, 1
    addi t0, t0, 1
    j get_two_count

    # while (b)
binary_gcd:
    # swap if a < b
    bgeu a0, a1, a_gte_b
    mv t2, a0
    mv a0, a1
    mv a1, t2
    # only after swapping might b become 0
    beqz a1, binary_gcd_end
a_gte_b:
    # make a odd
    andi t2, a0, 1
    beq t2, t1, a_odd # a&1 == 1
    srli a0, a0, 1
    # combine condition with jumping in one instruction
    # a>=b needs to be checked because a is getting smaller
    bnez a1, binary_gcd
a_odd:
    # make b odd
    andi t2, a1, 1
    beq t2, t1, b_odd # b&1 == 1
    srli a1, a1, 1
    # b won't be zero here because even >>= 1 > 0
    # and a>=b is true because b is getting smaller
    j a_odd
b_odd:
    sub a0, a0, a1
    srli a0, a0, 1
    # b won't be zero here
    j binary_gcd
binary_gcd_end:
    sll a0, a0, t0 # a << two_count
    ret
ret_b:
    mv a0, a1
ret_a:
    # a is already in a0
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
