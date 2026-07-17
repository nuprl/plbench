#include <stdio.h>

#include "accumulate.h"

int main(void) {
  int sum = 0;

#pragma omp parallel for
  for (int i = 0; i < 100; ++i)
    accumulate(&sum, i);

  printf("%d\n", sum);
  return 0;
}
