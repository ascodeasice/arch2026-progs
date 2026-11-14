#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (!a)
        return b;
    if (!b)
        return a;

    uint32_t two_count = 0;

    /* both even, divide by 2 */
    while (!(a & 1) && !(b & 1)) {
        a >>= 1;
        b >>= 1;
        two_count++;
    }

    while (b) {
        if (a < b) {
            uint32_t t = a;
            a = b;
            b = t;
        }

        if (!(a & 1) && (b & 1)) {
            /* even, odd */
            a >>= 1;
        } else if ((a & 1) && !(b & 1)) {
            /* odd, even */
            b >>= 1;
        } else {
            /* odd, odd: gcd((a-b)/2,b) */
            a = (a - b) >> 1;
        }
    }
    return a << two_count;
}
