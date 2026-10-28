int hello_add(int a, int b) { return a + b; }

int hello_apply(int (*f)(int, int), int a, int b) { return f(a, b); }
