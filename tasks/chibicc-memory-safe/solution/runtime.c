#define _GNU_SOURCE
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>

#define CAP_TAG  UINT64_C(0xcafe000000000000)
#define CAP_MASK UINT64_C(0xffff000000000000)
#define CAP_IDS  UINT64_C(0x0000ffffffffffff)

typedef enum { OBJ_GLOBAL, OBJ_STACK, OBJ_HEAP } ObjectKind;

typedef struct Object Object;
typedef struct Capability Capability;

struct Object {
  Object *next;
  uint64_t id;
  uintptr_t start;
  size_t size;
  uintptr_t frame;
  ObjectKind kind;
  int live;
  int marked;
};

struct Capability {
  Capability *next;
  uint64_t token;
  uint64_t object_id;
  uintptr_t lower;
  uintptr_t upper;
  uintptr_t cursor;
};

static Object *objects;
static Capability *capabilities;
static uint64_t next_object_id = 1;
static size_t live_heap_bytes;
static Object *temporary_heap_root;
static uint64_t capability_tag;

// Collection is deliberately frequent and simple. This keeps the oracle's
// memory footprint predictable and makes GC behavior observable in tests.
#define GC_THRESHOLD (32 * 1024 * 1024)

__attribute__((noreturn))
static void fail(const char *message, const void *pointer) {
  fprintf(stderr, "RUNTIME ERROR: %s (%p)\n", message, pointer);
  fflush(stderr);
  _Exit(255);
}

static int is_token(const void *pointer) {
  return capability_tag && (((uintptr_t)pointer) & CAP_MASK) == capability_tag;
}

void __safe_integer_overflow(void) {
  fail("integer arithmetic overflow", NULL);
}

static Capability *find_capability(const void *pointer) {
  uintptr_t token = (uintptr_t)pointer;
  if (!is_token(pointer))
    return NULL;
  for (Capability *cap = capabilities; cap; cap = cap->next)
    if (cap->token == token)
      return cap;
  return NULL;
}

static Object *find_object_id(uint64_t id) {
  for (Object *object = objects; object; object = object->next)
    if (object->id == id && object->live)
      return object;
  return NULL;
}

static Object *find_object(uintptr_t address, int allow_one_past) {
  Object *best = NULL;
  for (Object *object = objects; object; object = object->next) {
    if (!object->live || address < object->start)
      continue;
    uintptr_t delta = address - object->start;
    if (delta < object->size || (allow_one_past && delta == object->size)) {
      if (!best || object->size < best->size)
        best = object;
    }
  }
  return best;
}

static Object *register_object(void *raw, size_t size, ObjectKind kind,
                               void *frame) {
  if (!raw && size)
    fail("cannot register a null object", raw);

  if (kind == OBJ_GLOBAL) {
    for (Object *object = objects; object; object = object->next)
      if (object->live && object->kind == OBJ_GLOBAL &&
          object->start == (uintptr_t)raw && object->size == size)
        return object;
  }

  Object *object = malloc(sizeof(*object));
  if (!object)
    fail("capability metadata allocation failed", raw);
  object->id = next_object_id++;
  object->start = (uintptr_t)raw;
  object->size = size;
  object->frame = (uintptr_t)frame;
  object->kind = kind;
  object->live = 1;
  object->marked = 0;
  object->next = objects;
  objects = object;
  return object;
}

static void *make_capability(Object *object, uintptr_t lower,
                             uintptr_t upper, uintptr_t cursor) {
  for (Capability *cap = capabilities; cap; cap = cap->next)
    if (cap->object_id == object->id && cap->lower == lower &&
        cap->upper == upper && cap->cursor == cursor)
      return (void *)(uintptr_t)cap->token;

  Capability *cap = malloc(sizeof(*cap));
  if (!cap)
    fail("capability metadata allocation failed", NULL);
  if (!capability_tag) {
    do {
      if (getrandom(&capability_tag, sizeof(capability_tag), 0) !=
          sizeof(capability_tag))
        fail("secure capability token generation failed", NULL);
      capability_tag &= CAP_MASK;
    } while (!capability_tag || capability_tag == CAP_TAG);
  }
  do {
    if (getrandom(&cap->token, sizeof(cap->token), 0) != sizeof(cap->token))
      fail("secure capability token generation failed", NULL);
    cap->token = capability_tag | (cap->token & CAP_IDS);
  } while (!cap->token ||
           find_capability((void *)(uintptr_t)cap->token));
  cap->object_id = object->id;
  cap->lower = lower;
  cap->upper = upper;
  cap->cursor = cursor;
  cap->next = capabilities;
  capabilities = cap;
  return (void *)(uintptr_t)cap->token;
}

void __safe_register_global(void *raw, size_t size) {
  register_object(raw, size, OBJ_GLOBAL, NULL);
}

void __safe_relocate_global_pointer(void **slot, intptr_t cursor_addend,
                                    intptr_t lower_addend, size_t bound_size) {
  void *raw = *slot;
  if (!raw)
    return;
  if (!bound_size)
    fail("unsupported global pointer initializer", raw);
  __int128 base = (__int128)(uintptr_t)raw - cursor_addend;
  __int128 lower_value = base + lower_addend;
  if (base < 0 || base > UINTPTR_MAX || lower_value < 0 ||
      lower_value > UINTPTR_MAX)
    fail("overflow in global pointer initializer", raw);
  uintptr_t lower = (uintptr_t)lower_value;
  Object *object = find_object(lower, bound_size == 0);
  if (!object || object->kind != OBJ_GLOBAL)
    fail("global pointer initializer has no registered target", raw);
  if (bound_size > object->size || lower - object->start > object->size - bound_size)
    fail("global pointer initializer exceeds target", raw);
  uintptr_t upper = lower + bound_size;
  if ((uintptr_t)raw < lower || (uintptr_t)raw > upper)
    fail("global pointer cursor is outside its bounds", raw);
  *slot = make_capability(object, lower, upper, (uintptr_t)raw);
}

void __safe_register_stack(void *raw, size_t size, void *frame) {
  register_object(raw, size, OBJ_STACK, frame);
}

void __safe_leave_frame(void *frame) {
  for (Object *object = objects; object; object = object->next)
    if (object->live && object->kind == OBJ_STACK &&
        object->frame == (uintptr_t)frame)
      object->live = 0;
}

void *__safe_from_raw(void *pointer, size_t size) {
  if (!pointer)
    return NULL;

  Object *object;
  uintptr_t cursor;
  uintptr_t outer_upper;
  Capability *cap = find_capability(pointer);
  if (cap) {
    object = find_object_id(cap->object_id);
    if (!object)
      fail("narrowing a stale capability", pointer);
    cursor = cap->cursor;
    outer_upper = cap->upper;
  } else if (is_token(pointer)) {
    fail("invalid capability token", pointer);
  } else {
    cursor = (uintptr_t)pointer;
    object = find_object(cursor, size == 0);
    if (!object) {
      // A VLA is allocated dynamically after the fixed locals were
      // registered. Its first decay is therefore its registration point.
      object = register_object(pointer, size, OBJ_STACK,
                               __builtin_frame_address(1));
    }
    outer_upper = object->start + object->size;
  }

  if (cursor > outer_upper || size > outer_upper - cursor)
    fail("subobject bounds exceed existing authority", pointer);
  return make_capability(object, cursor, cursor + size, cursor);
}

void *__safe_from_raw_global(void *pointer, size_t size) {
  if (!pointer)
    return NULL;
  Object *object = find_object((uintptr_t)pointer, size == 0);
  if (!object)
    object = register_object(pointer, size, OBJ_GLOBAL, NULL);
  uintptr_t cursor = (uintptr_t)pointer;
  if (cursor > object->start + object->size ||
      size > object->start + object->size - cursor)
    fail("global bounds exceed registered object", pointer);
  return make_capability(object, cursor, cursor + size, cursor);
}

void *__safe_narrow(void *pointer, size_t size) {
  if (!pointer)
    return NULL;
  Capability *cap = find_capability(pointer);
  if (!cap)
    fail("narrowing a pointer without authority", pointer);
  Object *object = find_object_id(cap->object_id);
  if (!object)
    fail("narrowing a stale capability", pointer);
  if (cap->cursor > cap->upper || size > cap->upper - cap->cursor)
    fail("subobject bounds exceed existing authority", pointer);
  return make_capability(object, cap->cursor, cap->cursor + size, cap->cursor);
}

void *__safe_add(void *pointer, intptr_t delta, int delta_is_unsigned) {
  if (!pointer && delta == 0)
    return NULL;

  Object *object;
  uintptr_t lower, upper, cursor;
  Capability *cap = find_capability(pointer);
  if (cap) {
    object = find_object_id(cap->object_id);
    if (!object)
      fail("arithmetic on a stale capability", pointer);
    lower = cap->lower;
    upper = cap->upper;
    cursor = cap->cursor;
  } else {
    fail("pointer arithmetic without authority", pointer);
  }

  if (delta_is_unsigned && (uintptr_t)delta > upper - cursor)
    fail("unsigned pointer offset exceeds capability bounds", pointer);
  __int128 result = (__int128)cursor + (__int128)delta;
  if (result < lower || result > upper)
    fail("pointer arithmetic exceeds capability bounds", pointer);
  return make_capability(object, lower, upper, (uintptr_t)result);
}

void *__safe_access(void *pointer, size_t size) {
  if (!pointer)
    fail("null pointer access", pointer);

  Capability *cap = find_capability(pointer);
  if (cap) {
    if (!find_object_id(cap->object_id))
      fail("use of a stale capability", pointer);
    if (cap->cursor < cap->lower || size > cap->upper - cap->lower ||
        cap->cursor - cap->lower > cap->upper - cap->lower - size)
      fail("access exceeds capability bounds", pointer);
    return (void *)cap->cursor;
  }
  fail("memory access without authority", pointer);
}

static uintptr_t pointer_cursor(void *pointer, uint64_t *object_id) {
  if (!pointer) {
    *object_id = 0;
    return 0;
  }
  Capability *cap = find_capability(pointer);
  if (cap) {
    if (!find_object_id(cap->object_id))
      fail("comparison using a stale capability", pointer);
    *object_id = cap->object_id;
    return cap->cursor;
  }
  if (is_token(pointer))
    fail("comparison using an invalid capability", pointer);
  *object_id = 0;
  return (uintptr_t)pointer;
}

uintptr_t __safe_pointer_to_integer(void *pointer) {
  uint64_t object_id;
  return pointer_cursor(pointer, &object_id);
}

void *__safe_integer_to_pointer(uintptr_t value) {
  if (!value)
    return NULL;
  // Integer values carry no object authority. Return a recognizable invalid
  // token so any later pointer operation reports a checked violation instead
  // of accidentally recovering authority from a reused native address.
  return (void *)(uintptr_t)CAP_TAG;
}

intptr_t __safe_diff(void *left, void *right) {
  uint64_t left_id, right_id;
  uintptr_t left_cursor = pointer_cursor(left, &left_id);
  uintptr_t right_cursor = pointer_cursor(right, &right_id);
  if (!left_id || left_id != right_id)
    fail("pointer subtraction requires capabilities for the same object", left);
  return (intptr_t)(left_cursor - right_cursor);
}

int __safe_compare(void *left, void *right, int operation) {
  uint64_t left_id, right_id;
  uintptr_t left_cursor = pointer_cursor(left, &left_id);
  uintptr_t right_cursor = pointer_cursor(right, &right_id);
  if (operation >= 2 && (!left_id || left_id != right_id))
    fail("ordered pointer comparison requires the same object", left);
  if (operation == 0)
    return left_cursor == right_cursor;
  if (operation == 1)
    return left_cursor != right_cursor;
  if (operation == 2)
    return left_cursor < right_cursor;
  return left_cursor <= right_cursor;
}

static void mark_object(Object *object);

// Scan at byte granularity so capabilities in packed structs are roots too.
// A tag match is not sufficient: find_capability also requires an exact token
// issued by this runtime, so arbitrary scalar data cannot retain an object.
static void scan_capabilities(uintptr_t start, size_t size) {
  if (size < sizeof(uintptr_t))
    return;
  for (size_t offset = 0; offset <= size - sizeof(uintptr_t); offset++) {
    uintptr_t candidate;
    memcpy(&candidate, (void *)(start + offset), sizeof(candidate));
    Capability *cap = find_capability((void *)candidate);
    if (!cap)
      continue;
    Object *target = find_object_id(cap->object_id);
    if (target && target->kind == OBJ_HEAP)
      mark_object(target);
  }
}

static void mark_object(Object *object) {
  if (!object || !object->live || object->kind != OBJ_HEAP || object->marked)
    return;
  object->marked = 1;
  scan_capabilities(object->start, object->size);
}

static void collect_garbage(uintptr_t stack_bottom) {
  for (Object *object = objects; object; object = object->next)
    object->marked = 0;

  mark_object(temporary_heap_root);

  // Globals are explicit roots. Scan the active native stack as well as the
  // registered automatic objects so expression temporaries pushed below a
  // frame's fixed locals cannot be collected during a nested allocation.
  uintptr_t stack_top = stack_bottom;
  for (Object *object = objects; object; object = object->next)
    if (object->live && object->kind == OBJ_STACK &&
        object->start + object->size > stack_top)
      stack_top = object->start + object->size;
  if (stack_top > stack_bottom)
    scan_capabilities(stack_bottom, stack_top - stack_bottom);

  for (Object *object = objects; object; object = object->next)
    if (object->live && object->kind != OBJ_HEAP)
      scan_capabilities(object->start, object->size);

  for (Object *object = objects; object; object = object->next) {
    if (!object->live || object->kind != OBJ_HEAP || object->marked)
      continue;
    object->live = 0;
    live_heap_bytes -= object->size;
    free((void *)object->start);
  }

  // A removed capability token remains unforgeable and recognizable by its
  // tag; future use reports an invalid capability. Its table node is no
  // longer needed once the corresponding object lifetime is dead.
  Capability **cap_link = &capabilities;
  while (*cap_link) {
    Capability *cap = *cap_link;
    if (find_object_id(cap->object_id)) {
      cap_link = &cap->next;
    } else {
      *cap_link = cap->next;
      free(cap);
    }
  }

  Object **object_link = &objects;
  while (*object_link) {
    Object *object = *object_link;
    if (object->live) {
      object_link = &object->next;
    } else {
      *object_link = object->next;
      free(object);
    }
  }
}

void __safe_collect(void) {
  collect_garbage((uintptr_t)__builtin_frame_address(0) +
                  2 * sizeof(void *));
}

void *__safe_malloc(size_t size) {
  uintptr_t mutator_stack =
      (uintptr_t)__builtin_frame_address(0) + 2 * sizeof(void *);
  if (live_heap_bytes + size > GC_THRESHOLD)
    collect_garbage(mutator_stack);
  void *raw = malloc(size ? size : 1);
  if (!raw) {
    collect_garbage(mutator_stack);
    raw = malloc(size ? size : 1);
    if (!raw)
      return NULL;
  }
  Object *object = register_object(raw, size, OBJ_HEAP, NULL);
  live_heap_bytes += size;
  return make_capability(object, object->start, object->start + size,
                         object->start);
}

void *__safe_calloc(size_t count, size_t size) {
  if (size && count > SIZE_MAX / size)
    return NULL;
  size_t total = count * size;
  void *cap = __safe_malloc(total);
  if (cap && total)
    memset(__safe_access(cap, total), 0, total);
  return cap;
}

static Object *heap_object(void *pointer, const char *operation) {
  Capability *cap = find_capability(pointer);
  Object *object = cap ? find_object_id(cap->object_id) : NULL;
  if (!object || object->kind != OBJ_HEAP || cap->cursor != object->start ||
      cap->lower != object->start)
    fail(operation, pointer);
  return object;
}

void __safe_free(void *pointer) {
  (void)pointer;
}

void *__safe_realloc(void *pointer, size_t size) {
  if (!pointer)
    return __safe_malloc(size);
  Object *old = heap_object(pointer, "realloc of an invalid capability");
  if (!size)
    return NULL;

  temporary_heap_root = old;
  void *replacement = __safe_malloc(size);
  if (!replacement) {
    temporary_heap_root = NULL;
    return NULL;
  }
  size_t copied = old->size < size ? old->size : size;
  if (copied)
    memcpy(__safe_access(replacement, copied), (void *)old->start, copied);
  temporary_heap_root = NULL;
  return replacement;
}

void *__safe_memcpy(void *destination, const void *source, size_t size) {
  void *raw_destination = size ? __safe_access(destination, size) : destination;
  const void *raw_source = size ? __safe_access((void *)source, size) : source;
  memmove(raw_destination, raw_source, size);
  return destination;
}

void *__safe_memmove(void *destination, const void *source, size_t size) {
  void *raw_destination = size ? __safe_access(destination, size) : destination;
  const void *raw_source = size ? __safe_access((void *)source, size) : source;
  memmove(raw_destination, raw_source, size);
  return destination;
}

void *__safe_memset(void *destination, int byte, size_t size) {
  void *raw = size ? __safe_access(destination, size) : destination;
  memset(raw, byte, size);
  return destination;
}

size_t __safe_strlen(const char *string) {
  Capability *cap = find_capability(string);
  if (!cap || !find_object_id(cap->object_id) || cap->cursor >= cap->upper)
    fail("strlen requires a live string capability", string);
  size_t available = cap->upper - cap->cursor;
  const char *raw = (const char *)cap->cursor;
  const char *end = memchr(raw, 0, available);
  if (!end)
    fail("unterminated string exceeds capability bounds", string);
  return (size_t)(end - raw);
}

char *__safe_strcpy(char *destination, const char *source) {
  size_t size = __safe_strlen(source) + 1;
  char *raw_destination = __safe_access(destination, size);
  const char *raw_source = __safe_access((void *)source, size);
  memmove(raw_destination, raw_source, size);
  return destination;
}

int __safe_printf(const char *format, ...) {
  size_t length = __safe_strlen(format);
  Capability *cap = find_capability(format);
  const char *raw_format = (const char *)cap->cursor;
  for (size_t i = 0; i < length; i++) {
    if (raw_format[i] != '%')
      continue;
    if (i + 1 < length && raw_format[i + 1] == '%') {
      i++;
      continue;
    }
    while (++i < length) {
      char conversion = raw_format[i];
      if (conversion == 's' || conversion == 'S' || conversion == 'n')
        fail("printf pointer conversion is outside the checked subset", format);
      if (strchr("diouxXfFeEgGaAcspn%", conversion))
        break;
    }
  }
  va_list arguments;
  va_start(arguments, format);
  int result = vprintf(raw_format, arguments);
  va_end(arguments);
  return result;
}
