#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    /*  a+b mod 2^32 */
    *n = 0;
    while (b) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        (*n)++;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    /* floor((a + b) / 2) of the exact sum, with no intermediate */
    return ((a ^ b) >> 1) + (a & b);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /* Q11.20 product, round toward positive infinity */
    uint64_t res = 0;
    uint64_t cur = a;
    for (int i = 0; i < 32; i++) {
        if (((uint32_t) b >> i) & 1) {
            if (i == 31) {
                /* two's complement */
                res -= cur;
            } else {
                res += cur;
            }
        }
        cur <<= 1;
    }

    res += (1u << (20 - 1)); /* add 2^(-19) to round up */
    res >>= 20;
    return (int32_t) (uint32_t) (res & 0xFFFFFFFF);
}
