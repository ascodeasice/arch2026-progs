#include "rubik.h"
#include "pdb.h"

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    MOVES = 9,
    MAX_DEPTH = 11  // diameter in half-turn metric
};

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};

static uint16_t rank_p(const uint8_t p[CUBIES])
{
    /* Lehmer rank */
    uint16_t r = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j)
            if (p[j] < p[i])
                ++smaller;
        r = (uint16_t) (r * (CUBIES - i) + smaller);
    }
    return r;
}

static uint16_t rank_o(const uint8_t o[CUBIES])
{
    uint16_t r = 0;
    for (uint8_t i = 0; i < 6; ++i)
        r = (uint16_t) (r * 3U + o[i]);
    return r;
}

static uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t hp = pdb_perm[p], ho = pdb_orient[o];
    /* prune more level by picking the larger ones */
    return hp > ho ? hp : ho;
}

static int search(uint16_t root_p,
                  uint16_t root_o,
                  uint8_t bound,
                  uint8_t moves[MAX_DEPTH])
{
    /* stack */
    uint16_t p[MAX_DEPTH + 1], o[MAX_DEPTH + 1];
    uint8_t face[MAX_DEPTH + 1];  /* 0,1,2 for R, B, D; 3 is none */
    uint8_t turns[MAX_DEPTH + 1]; /* 0, 1, 2 for 90,180,270 */

    /* push root to stack, we need initial state to make turn in depth 1 */
    p[0] = root_p;
    o[0] = root_o;
    face[0] = 3;

    /* start by first face and first turn */
    face[1] = 0; /* turns to make */
    turns[1] = 0;
    p[1] = root_p; /* state from parent */
    o[1] = root_o;

    uint8_t depth = 1;

    while (depth > 0) {
        if (turns[depth] < 3) {
            /* try current turn then update */
            const move_t *mp = &move_perm[face[depth]][p[depth]];
            const move_t *mo = &move_orient[face[depth]][o[depth]];

            p[depth] = mp->next;
            o[depth] = mo->next;
            turns[depth]++; /* turn angle to be tried */

            int left = bound - depth;

            if (mp->h > left || mo->h > left) {
                /* this path won't fit bound */
                continue;
            }

            if (left == 0) {
                /* h == 0 only when solved in the table
                 * solution can only be found at left==0 because a solution with
                 * lower length would've been found with lower bound
                 */
                for (int i = 1; i <= depth; i++) {
                    /* -1 because turns had an extra ++ */
                    moves[i - 1] = (uint8_t) (face[i] * 3 + turns[i] - 1);
                }
                return depth;
            }

            /* make turn then try next cube */
            depth++;

            /* first different face, 0=>1;1=>0;2=>0 */
            face[depth] = face[depth - 1] == 0;
            turns[depth] = 0;
            p[depth] = p[depth - 1];
            o[depth] = o[depth - 1];
            continue;
        }

        /* all turn tried, try next face */
        uint8_t next_face = (uint8_t) (face[depth] + 1);
        if (next_face == face[depth - 1]) {
            next_face++;
        }

        if (next_face >= 3) {
            /* pop */
            depth--;
            continue;
        }

        face[depth] = next_face;
        turns[depth] = 0;
        /* copy perm and face from parent */
        p[depth] = p[depth - 1];
        o[depth] = o[depth - 1];
    }

    return -1;
}

static int solve(uint16_t p, uint16_t o, uint8_t moves[MAX_DEPTH])
{
    if (p == 0 && o == 0) {
        return 0;
    }
    for (uint8_t bound = heuristic(p, o); bound <= MAX_DEPTH; bound++) {
        int length = search(p, o, bound, moves);
        if (length >= 0) {
            return length;
        }
    }
    return -1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    /* SECTION: return -1 if invalid */
    /* wrong length */
    for (int i = 0; i < 14; i++) {
        if (state[i] == '\0') {
            return -1;
        }
    }
    if (state[14] != '\0') {
        return -1;
    }

    uint8_t p[7] = {};
    uint8_t o[7] = {};

    for (int i = 0; i < 7; i++) {
        /* out of range digit */
        if (state[i] < '1' || state[i] > '7') {
            return -1;
        }
        p[i] = (uint8_t) (state[i] - '1');
    }

    /* repeated cubie */
    for (int i = 0; i < 7; i++) {
        for (int j = i + 1; j < 7; j++) {
            if (p[i] == p[j]) {
                return -1;
            }
        }
    }

    /* orientation sum not multiple of 3 */
    uint8_t sum = 0;
    for (int i = 0; i < 7; i++) {
        if (state[i + 7] < '1' || state[i + 7] > '3') {
            return -1;
        }
        o[i] = (uint8_t) (state[i + 7] - '1');
        sum += o[i];
    }

    while (sum >= 3) {
        sum -= 3;
    }
    if (sum != 0) {
        return -1;
    }

    if (cap == 0) {
        /* even for solved cube, "\0" requires cap >= 1 */
        return -2;
    }

    /* SECTION: solve cube */
    uint8_t moves[MAX_DEPTH];

    /* all solvable */
    int length = solve(rank_p(p), rank_o(o), moves);

    /* return -2 if solution and NUL doesn't fit cap bytes, set out[0]
     * to \0 if cap>=1
     */
    size_t j = 0; /* cur out length */
    for (int i = 0; i < length; i++) {
        for (int k = 0; move_names[moves[i]][k] != '\0'; k++) {
            if ((j + 1) >= cap) {
                /* no place for NUL; cap >= 1 was checked above */
                out[0] = '\0';
                return -2;
            }
            out[j] = move_names[moves[i]][k];
            j++;
        }
        if (i < length - 1) {
            out[j] = ' ';
            j++;
        }
    }
    out[j] = '\0';

    return length;
}
