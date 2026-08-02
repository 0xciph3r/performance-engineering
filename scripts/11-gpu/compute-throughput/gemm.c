#define _POSIX_C_SOURCE 200809L

#include <Accelerate/Accelerate.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// float32 single precision throughout (the precision GPU workloads use)

static inline double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

// worst-order scalar: inner loop walks B column (stride n)
static void gemm_ijk(const float *A, const float *B, float *C, int n) {
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) {
      float acc = 0.0f;
      for (int k = 0; k < n; k++) acc += A[i * n + k] * B[k * n + j];
      C[i * n + j] = acc;
    }
}

// best-order scalar: inner loop walks B row (contiguous)
static void gemm_ikj(const float *A, const float *B, float *C, int n) {
  for (int i = 0; i < n; i++)
    for (int k = 0; k < n; k++) {
      const float a = A[i * n + k];
      for (int j = 0; j < n; j++) C[i * n + j] += a * B[k * n + j];
    }
}

static float max_err(const float *a, const float *b, size_t n) {
  float e = 0.0f, s = 0.0f;
  for (size_t i = 0; i < n; i++) {
    float d = a[i] - b[i];
    if (d < 0) d = -d;
    if (d > e) e = d;
    if (a[i] < 0) s += -a[i]; else s += a[i];
  }
  return e / (s / (float)n);
}

static void run_gemm(int n, int trials) {
  size_t sz = (size_t)n * n;
  float *A = malloc(sz * sizeof(float));
  float *B = malloc(sz * sizeof(float));
  float *C_ref = malloc(sz * sizeof(float));
  float *C_out = malloc(sz * sizeof(float));
  srand(42);
  for (size_t i = 0; i < sz; i++) {
    A[i] = (float)(rand() % 1000) / 1000.0f;
    B[i] = (float)(rand() % 1000) / 1000.0f;
  }
  memset(C_ref, 0, sz * sizeof(float));
  memset(C_out, 0, sz * sizeof(float));

  cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n, 1.0f, A, n, B, n, 0.0f, C_ref, n);

  struct { const char *name; void (*fn)(const float *, const float *, float *, int); } kernels[] = {
    {"naive_ijk", gemm_ijk},
    {"naive_ikj", gemm_ikj},
  };

  for (size_t k = 0; k < sizeof(kernels) / sizeof(kernels[0]); k++) {
    double best = 1e30;
    for (int t = 0; t < trials; t++) {
      memset(C_out, 0, sz * sizeof(float));
      double t0 = now_ms();
      kernels[k].fn(A, B, C_out, n);
      double t1 = now_ms();
      if (t1 - t0 < best) best = t1 - t0;
    }
    double gflops = 2.0 * n * n * n / (best * 1e-3) / 1e9;
    float err = max_err(C_out, C_ref, sz);
    printf("gemm method=%s n=%d best_ms=%.1f gflops=%.2f rel_err=%g\n", kernels[k].name, n, best, gflops, err);
  }

  {
    double best = 1e30;
    for (int t = 0; t < trials; t++) {
      memset(C_out, 0, sz * sizeof(float));
      double t0 = now_ms();
      cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n, 1.0f, A, n, B, n, 0.0f, C_out, n);
      double t1 = now_ms();
      if (t1 - t0 < best) best = t1 - t0;
    }
    double gflops = 2.0 * n * n * n / (best * 1e-3) / 1e9;
    float err = max_err(C_out, C_ref, sz);
    printf("gemm method=blas_sgemm n=%d best_ms=%.1f gflops=%.2f rel_err=%g\n", n, best, gflops, err);
  }

  free(A); free(B); free(C_ref); free(C_out);
}

// elementwise add/mul: scalar loop vs vDSP (Accelerate, NEON)
static void run_elem(int n, int k, int trials) {
  float *A = malloc(n * sizeof(float));
  float *B = malloc(n * sizeof(float));
  float *C = malloc(n * sizeof(float));
  for (int i = 0; i < n; i++) { A[i] = (float)i; B[i] = 1.0f / (float)(i + 1); }

  struct { const char *name; double (*fn)(float *, const float *, const float *, int); } ops[] = {
    {"add", NULL},
    {"mul", NULL},
  };

  for (size_t o = 0; o < 2; o++) {
    // scalar
    double best = 1e30;
    for (int t = 0; t < trials; t++) {
      double t0 = now_ms();
      if (o == 0)
        for (int r = 0; r < k; r++)
          for (int i = 0; i < n; i++) C[i] = A[i] + B[i];
      else
        for (int r = 0; r < k; r++)
          for (int i = 0; i < n; i++) C[i] = A[i] * B[i];
      double t1 = now_ms();
      if (t1 - t0 < best) best = t1 - t0;
    }
    double bytes = (double)n * 12.0 * k;
    printf("elem method=scalar op=%s n=%d best_ms=%.2f gb_per_s=%.1f\n", ops[o].name, n, best, bytes / (best * 1e-3) / 1e9);

    // vDSP
    best = 1e30;
    for (int t = 0; t < trials; t++) {
      double t0 = now_ms();
      for (int r = 0; r < k; r++) {
        if (o == 0) vDSP_vadd(A, 1, B, 1, C, 1, (vDSP_Length)n);
        else        vDSP_vmul(A, 1, B, 1, C, 1, (vDSP_Length)n);
      }
      double t1 = now_ms();
      if (t1 - t0 < best) best = t1 - t0;
    }
    printf("elem method=vdsp op=%s n=%d best_ms=%.2f gb_per_s=%.1f\n", ops[o].name, n, best, bytes / (best * 1e-3) / 1e9);
  }
  free(A); free(B); free(C);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: %s <gemm|elem>\n", argv[0]); return 1; }
  if (strcmp(argv[1], "gemm") == 0) {
    run_gemm(128, 5);
    run_gemm(256, 5);
    run_gemm(512, 3);
    run_gemm(1024, 2);
    run_gemm(2048, 2);
  } else if (strcmp(argv[1], "elem") == 0) {
    run_elem(1 << 20, 300, 3);
  } else { fprintf(stderr, "unknown: %s\n", argv[1]); return 1; }
  return 0;
}
