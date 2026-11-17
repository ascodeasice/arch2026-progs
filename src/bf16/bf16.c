#include "bf16.h"

#define BF16_SIGN 0x8000u
#define BF16_INF 0x7F80u
#define BF16_NAN 0x7FC0u
#define BF16_BIAS 127

uint16_t bf16_from_f32(uint32_t f32bits)
{
    /* Inf and NaN keep their top half; rounding could turn a NaN into Inf. */
    if (((f32bits >> 23) & 0xFF) == 0xFF)
        return (uint16_t) (f32bits >> 16);
    /*
     * Round to nearest, ties to even: a discarded half above 0x8000 carries
     * into bit 16, and so does exactly 0x8000 when bit 16 is already odd.
     * The carry may ripple into the exponent; the largest finite value then
     * becomes Inf, as the contract says.
     */
    f32bits += 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) (f32bits >> 16);
}

/*
 * Product of two significands in [128, 256) by shift-and-add over the bits of
 * y, since RV32I has no multiply. The result fits in 16 bits.
 */
static uint32_t mul8x8(uint32_t x, uint32_t y)
{
    uint32_t p = 0;
    while (y) {
        if (y & 1u)
            p += x;
        x <<= 1;
        y >>= 1;
    }
    return p;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (uint32_t) (a ^ b) & BF16_SIGN;
    int32_t exp_a = (a >> 7) & 0xFF, exp_b = (b >> 7) & 0xFF;
    uint32_t mant_a = a & 0x7Fu, mant_b = b & 0x7Fu;

    /* a is examined first, so an infinite a swallows a NaN b. */
    if (exp_a == 0xFF) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return BF16_NAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if (exp_b == 0xFF) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return BF16_NAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (uint16_t) sign;

    /*
     * A denormal has no hidden one: shift its fraction up until bit 7 is set
     * and count the shifts against the exponent, which is 1 for denormals.
     */
    int32_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80u)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80u;
    }
    if (!exp_b) {
        while (!(mant_b & 0x80u)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80u;
    }

    /*
     * The product of two values in [128, 256) lies in [2^14, 2^16). When it
     * reaches bit 15 the significand is one bit wider, so shift one more and
     * raise the exponent. The dropped bits are truncated, not rounded.
     */
    uint32_t mant = mul8x8(mant_a, mant_b);
    int32_t exp = exp_a + exp_b - BF16_BIAS + exp_adjust;
    if (mant & 0x8000u) {
        mant = (mant >> 8) & 0x7Fu;
        exp++;
    } else {
        mant = (mant >> 7) & 0x7Fu;
    }

    if (exp >= 0xFF)
        return (uint16_t) (sign | BF16_INF);
    if (exp <= 0) {
        /*
         * NOTE: the fraction is shifted without its hidden one, as the quiz
         * code and the contract do.
         */
        if (exp < -6)
            return (uint16_t) sign;
        mant >>= 1 - exp;
        exp = 0;
    }
    return (uint16_t) (sign | ((uint32_t) exp << 7) | mant);
}

/*
 * Integer square root of n < 2^16 by the digit-by-digit method: one result bit
 * per step, from bit 7 down, with no multiply. root holds the bits found so
 * far scaled by 2^(bit + 1) and rem the remainder n - root^2 of that prefix.
 */
static uint32_t isqrt16(uint32_t n)
{
    uint32_t root = 0, one = 1u << 14;
    while (one) {
        if (n >= root + one) {
            n -= root + one;
            root = (root >> 1) + one;
        } else {
            root >>= 1;
        }
        one >>= 2;
    }
    return root;
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exp = (a >> 7) & 0xFF, mant = a & 0x7Fu;

    if (exp == 0xFF) {
        if (mant)
            return a; /* NaN, either sign */
        return (a & BF16_SIGN) ? BF16_NAN : a;
    }
    if (!(a & 0x7FFFu))
        return 0; /* sqrt(-0) is +0 */
    if (a & BF16_SIGN)
        return BF16_NAN; /* negative denormals included */
    if (!exp)
        return 0; /* positive denormals flush to +0 */

    /*
     * a = 2^(exp - 127) * m / 128 with m in [128, 256). An odd unbiased
     * exponent, that is an even exp, is made even by doubling m, so m / 128
     * lies in [1, 4) and its square root in [1, 2). The halved exponent is
     * floor((exp - 127) / 2) + 127, which equals (exp + 127) / 2 rounded down
     * for both parities.
     */
    uint32_t m = 0x80u | mant;
    if (!(exp & 1))
        m <<= 1;
    uint32_t new_exp = (exp + BF16_BIAS) >> 1;

    /*
     * The contract asks for the largest r with (r * r) / 128 <= m, truncating:
     * r * r < 128 * (m + 1), so r is the integer square root of 128 * m + 127.
     * For m in [128, 512) r lies in [128, 256), already normalized, and
     * new_exp in [64, 190], so neither Inf nor zero can come out here.
     */
    uint32_t r = isqrt16((m << 7) + 127);
    return (uint16_t) ((new_exp << 7) | (r & 0x7Fu));
}
