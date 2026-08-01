#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

typedef uint32_t data_t;

static inline double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

// Diagonal-layout accessor: A(i, j) lives at A[N + i - j - 1] (2N-1 array)
#define A(i, j) A[(N) + (i) - (j) - 1]

static inline data_t f(data_t a, data_t b, data_t c) {
  return a ^ b ^ c;
}

// Iterative formulation: fill row by row
static void tableau_iter(data_t *A, size_t N) {
  for (size_t i = 1; i < N; i++) {
    for (size_t j = 1; j < N; j++) {
      A(i, j) = f(A(i - 1, j - 1), A(i, j - 1), A(i - 1, j));
    }
  }
}

// Recursive 4-way formulation: divide [rbegin,rend)x[cbegin,cend) into quadrants
static void tableau_rec(data_t *A, size_t N,
                        size_t rbegin, size_t rend,
                        size_t cbegin, size_t cend) {
  if (rend - rbegin == 1 && cend - cbegin == 1) {
    size_t i = rbegin, j = cbegin;
    A(i, j) = f(A(i - 1, j - 1), A(i, j - 1), A(i - 1, j));
  } else {
    size_t rmid = rend - rbegin > 1 ? (rbegin + (rend - rbegin) / 2) : rend;
    size_t cmid = cend - cbegin > 1 ? (cbegin + (cend - cbegin) / 2) : cend;
    tableau_rec(A, N, rbegin, rmid, cbegin, cmid);
    if (cend > cmid)
      tableau_rec(A, N, rbegin, rmid, cmid, cend);
    if (rend > rmid)
      tableau_rec(A, N, rmid, rend, cbegin, cmid);
    if (rend > rmid && cend > cmid)
      tableau_rec(A, N, rmid, rend, cmid, cend);
  }
}

static void init(data_t *A, size_t N, data_t val) {
  for (size_t i = 0; i < N; i++) A(i, 0) = val;
  for (size_t j = 0; j < N; j++) A(0, j) = val;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s <iterative|recursive> <N>\n", argv[0]);
    return 1;
  }
  const char *method = argv[1];
  size_t N = strtoul(argv[2], NULL, 10);

  data_t *A = malloc((2 * N - 1) * sizeof(data_t));
  if (A == NULL) return 1;

  init(A, N, 7);
  double t0 = now_ms();
  if (strcmp(method, "iterative") == 0) {
    tableau_iter(A, N);
  } else if (strcmp(method, "recursive") == 0) {
    tableau_rec(A, N, 1, N, 1, N);
  } else {
    fprintf(stderr, "unknown method: %s\n", method);
    return 1;
  }
  double t1 = now_ms();

  printf("method=%s N=%zu elapsed_ms=%.2f result=%u\n", method, N, t1 - t0,
         A(N - 1, N - 1));
  free(A);
  return 0;
}
