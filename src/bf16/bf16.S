# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.
#
# The arguments are uint16_t, which the calling convention zero-extends to 32
# bits, so bits 31..16 of a0 and a1 are zero on entry to the multiply and the
# square root. Every function is a leaf and uses temporaries only.

    .text

# bf16_from_f32_asm: round a binary32 pattern to nearest, ties to even.
#
#   a0  the binary32 pattern, then the result
#   t0  exponent field in place, then bits 16..0 shifted to the top
#   t1  0x7F800000, then 0x40000000, then 0x8000
#
# The contract adds 0x7FFF plus bit 16 and keeps the top half. That equals
# adding 0x8000, except for an exact tie (discarded half 0x8000) with an even
# bit 16: there 0x8000 carries and 0x7FFF does not, and the result is the top
# half unchanged. Testing for that one pattern costs 3 instructions; forming
# 0x7FFF plus bit 16 costs 4 (shift, mask and a 2-instruction constant).
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t1, 0x7F800
    and     t0, a0, t1
    beq     t0, t1, 1f              # exponent 0xFF: Inf or NaN, keep the top half
    slli    t0, a0, 15              # bit 16 to bit 31, bits 15..0 to 30..15
    lui     t1, 0x40000
    beq     t0, t1, 1f              # tie with an even bit 16: keep the top half
    lui     t1, 8
    add     a0, a0, t1              # round half up; may carry into the exponent
1:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# bf16_mul_asm: product with a truncated fraction.
#
#   a0  a, then the result
#   a1  b; on the slow path its normalized significand
#   a2  product accumulator (Horner step destination), then the significand
#   a3  sign of the product in bit 15
#   t0  exponent field of a, then the effective exponent, then result exp - 1
#   t1  exponent field of b, then the effective exponent, then bit 15 of the
#       product
#   t2  exponent of a minus 1, scratch
#   t3  exponent of b minus 1
#   t4  254
#   t5  significand of a with its leading one (bit 7)
#   t6  product accumulator (Horner step source)
#
# Fast path: both exponent fields in [1, 254]. The 8-bit by 8-bit product is
# formed by Horner's rule from the top bit of b down, p = 2p + bit * ma, with
# the 7 remaining bits of b parked in bits 31..25 of the accumulator: bgez
# tests the next bit for free, and the shift that doubles p moves the next bit
# up. p stays below 2^16, so it never reaches the parked bits. Each bit costs
# 2 instructions, or 3 when it is set; the compiler's loop spends 5 to 6.
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     a3, a0, a1
    srli    a3, a3, 15
    slli    a3, a3, 15              # sign of the product
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    srli    t1, a1, 7
    andi    t1, t1, 0xFF
    addi    t2, t0, -1
    addi    t3, t1, -1
    li      t4, 254
    bgeu    t2, t4, .Lmul_slow      # exponent of a is 0 or 0xFF
    bgeu    t3, t4, .Lmul_slow      # exponent of b is 0 or 0xFF
    andi    t5, a0, 0x7F
    ori     t5, t5, 0x80            # ma = 1.fraction of a, times 128
.Lmul_core:
    # t0, t1: effective exponents; t5: ma; a1: mb with bit 7 set, of which
    # only bits 6..0 are read. Bit 7 of mb is 1, so p starts at ma.
    slli    t6, a1, 25
    or      t6, t6, t5
    slli    a2, t6, 1               # bit 6 of mb
    bgez    t6, 1f
    add     a2, a2, t5
1:
    slli    t6, a2, 1               # bit 5
    bgez    a2, 1f
    add     t6, t6, t5
1:
    slli    a2, t6, 1               # bit 4
    bgez    t6, 1f
    add     a2, a2, t5
1:
    slli    t6, a2, 1               # bit 3
    bgez    a2, 1f
    add     t6, t6, t5
1:
    slli    a2, t6, 1               # bit 2
    bgez    t6, 1f
    add     a2, a2, t5
1:
    slli    t6, a2, 1               # bit 1
    bgez    a2, 1f
    add     t6, t6, t5
1:
    slli    a2, t6, 1               # bit 0; the parked bits are all out now
    bgez    t6, 1f
    add     a2, a2, t5
1:
    # a2 = ma * mb in [2^14, 2^16). Renormalize by one more bit when it
    # reached bit 15. The significand keeps its leading one, which adds 1 to
    # the exponent field when the two are added, so t0 holds exponent - 1:
    # exp_a + exp_b - 127 + carry - 1.
    add     t0, t0, t1
    srli    t1, a2, 15
    add     t0, t0, t1
    addi    t0, t0, -128
    srl     a2, a2, t1
    srli    a2, a2, 7               # significand in [128, 256)
    bgeu    t0, t4, .Lmul_range     # exponent - 1 outside [0, 253]
    slli    t0, t0, 7
    add     a0, t0, a2              # leading one carries exponent - 1 to exponent
    or      a0, a0, a3
    ret

.Lmul_range:
    # Result exponent >= 0xFF overflows; <= 0 is denormal or zero.
    bge     t0, t4, .Lmul_inf
    li      t1, -7
    blt     t0, t1, .Lmul_zero      # exponent < -6
    andi    a2, a2, 0x7F            # the contract drops the leading one here
    neg     t0, t0                  # 1 - exponent
    srl     a2, a2, t0
    or      a0, a2, a3
    ret

.Lmul_slow:
    # An exponent field is 0 or 0xFF. a is examined before b. t2 and t3 hold
    # the fields minus 1, so 254 in t4 marks 0xFF.
    andi    t5, a0, 0x7F
    andi    t6, a1, 0x7F
    bne     t2, t4, 1f
    bnez    t5, .Lmul_ret           # NaN a is returned unchanged
    slli    t2, a1, 17
    beqz    t2, .Lmul_nan           # Inf times zero
    j       .Lmul_inf               # Inf times anything else, NaN b included
1:
    bne     t3, t4, 2f
    bnez    t6, .Lmul_ret_b         # NaN b is returned unchanged
    slli    t2, a0, 17
    beqz    t2, .Lmul_nan
    j       .Lmul_inf
2:
    slli    t2, a0, 17
    beqz    t2, .Lmul_zero          # a is a zero, b finite
    slli    t2, a1, 17
    beqz    t2, .Lmul_zero          # b is a zero
    # Both finite and nonzero, at least one denormal. A denormal has the
    # exponent of 1 and no leading one: shift its fraction up until bit 7 is
    # set, one exponent step per shift.
    bnez    t0, 3f
    li      t0, 1
4:
    slli    t5, t5, 1
    addi    t0, t0, -1
    andi    t2, t5, 0x80
    beqz    t2, 4b
3:
    ori     t5, t5, 0x80            # leading one; already set after the loop
    bnez    t1, 6f
    li      t1, 1
7:
    slli    t6, t6, 1
    addi    t1, t1, -1
    andi    t2, t6, 0x80
    beqz    t2, 7b
6:
    mv      a1, t6                  # bit 7 of a normal b is never read
    j       .Lmul_core

.Lmul_inf:
    li      a0, 0x7F80
    or      a0, a0, a3
    ret
.Lmul_nan:
    li      a0, 0x7FC0
    ret
.Lmul_zero:
    mv      a0, a3
    ret
.Lmul_ret_b:
    mv      a0, a1
.Lmul_ret:
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

# bf16_sqrt_asm: the contract's truncating square root.
#
#   a0  a, then the result
#   t0  a >> 7 (sign and exponent field), then result exponent - 1
#   t1  t0 - 1, for the range check
#   t2  254
#   t3  n = 128 * m + 127, then the remainder n - root^2
#   t4  exponent parity, then root (the result bits found so far, scaled)
#   t5  trial value root + one
#
# For a positive normal, a = 2^(exp - 127) * m / 128 with m in [128, 512)
# after the odd unbiased exponent is made even by doubling m. The contract's
# result is the largest r with r * r < 128 * (m + 1), the integer square root
# of n = 128 * m + 127, which lies in [128, 256). It is found by the
# digit-by-digit method, unrolled with the constants one = 4^k folded in:
#     t = root + one; root >>= 1; if (n >= t) { n -= t; root += one; }
# The first two digits are known or decided by one compare against
# (128 + 64)^2. The result exponent is (exp + 127) / 2 rounded down for both
# parities, and r keeps its leading one, so t0 holds that exponent minus 1.
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    addi    t1, t0, -1
    li      t2, 254
    bgeu    t1, t2, .Lsqrt_special  # not a positive normal
    andi    t3, a0, 0x7F
    ori     t3, t3, 0x80
    andi    t4, t0, 1               # 1: odd exponent field, even unbiased one
    slli    t3, t3, 8
    srl     t3, t3, t4              # 128 * m
    addi    t3, t3, 127             # n
    addi    t0, t0, 125
    srli    t0, t0, 1               # result exponent - 1
    # Digits 7 and 6: n >= 128^2 always; n >= 192^2 decides digit 6.
    lui     t5, 9                   # 36864 = 192^2
    bltu    t3, t5, 1f
    sub     t3, t3, t5
    lui     t4, 3                   # root = 12288 (r = 192 so far)
    j       2f
1:
    lui     t5, 4                   # 16384 = 128^2
    sub     t3, t3, t5
    lui     t4, 2                   # root = 8192 (r = 128 so far)
2:
    addi    t5, t4, 1024            # digit 5
    srli    t4, t4, 1
    bltu    t3, t5, 1f
    sub     t3, t3, t5
    addi    t4, t4, 1024
1:
    addi    t5, t4, 256             # digit 4
    srli    t4, t4, 1
    bltu    t3, t5, 1f
    sub     t3, t3, t5
    addi    t4, t4, 256
1:
    addi    t5, t4, 64              # digit 3
    srli    t4, t4, 1
    bltu    t3, t5, 1f
    sub     t3, t3, t5
    addi    t4, t4, 64
1:
    addi    t5, t4, 16              # digit 2
    srli    t4, t4, 1
    bltu    t3, t5, 1f
    sub     t3, t3, t5
    addi    t4, t4, 16
1:
    addi    t5, t4, 4               # digit 1
    srli    t4, t4, 1
    bltu    t3, t5, 1f
    sub     t3, t3, t5
    addi    t4, t4, 4
1:
    addi    t5, t4, 1               # digit 0: the remainder is not needed
    srli    t4, t4, 1
    bltu    t3, t5, 1f
    addi    t4, t4, 1
1:
    slli    t0, t0, 7
    add     a0, t0, t4              # leading one carries exponent - 1 to exponent
    ret

.Lsqrt_special:
    beqz    t0, .Lsqrt_zero         # +0 and positive denormals
    beq     t1, t2, .Lsqrt_ret      # +Inf and positive NaN: unchanged
    slli    t3, a0, 17              # magnitude at the top
    beqz    t3, .Lsqrt_zero         # -0 gives +0
    lui     t4, 0xFF000             # 0x7F80 << 17, the magnitude of Inf
    bltu    t4, t3, .Lsqrt_ret      # negative NaN: unchanged
    li      a0, 0x7FC0              # -Inf and negative nonzero values
.Lsqrt_ret:
    ret
.Lsqrt_zero:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
