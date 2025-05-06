#ifndef MIRA_H
#define MIRA_H

// temporary
#define MIRA_IMPLEMENTATION
#define MIRA_GENERATE_MAIN

enum mira_error {
    MIRA_NO_ERROR,
    MIRA_STACK_OVERFLOW,
    MIRA_STACK_UNDERFLOW,
    MIRA_TUPLE_OVERFLOW,
};

#ifdef MIRA_IMPLEMENTATION

#include <stdint.h>
#include <stddef.h>

#warning remove that later
#include <assert.h>

#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))

#define MIRA_MAX_ARITY 1
#define MIRA_STACK_SIZE 1024

typedef uint32_t intern_t;

#define TUPLE_DECL(arity) \
    typedef struct tuple##arity##_t { \
        intern_t data[arity]; \
        size_t ptr; \
    } tuple##arity##_t; \

TUPLE_DECL(1)

static tuple1_t stack0[MIRA_STACK_SIZE];
static tuple1_t stack1[MIRA_STACK_SIZE];
static tuple1_t stack2[MIRA_STACK_SIZE];

static size_t sptr0 = 0;
static size_t sptr1 = 0;
static size_t sptr2 = 0;

static size_t bsptr0 = 0;
static size_t bsptr1 = 0;
static size_t bsptr2 = 0;

static void save_stack_pointers() {
    bsptr0 = sptr0;
    bsptr1 = sptr1;
    bsptr2 = sptr2;
}

static void restore_stack_pointers() {
    sptr0 = bsptr0;
    sptr1 = bsptr1;
    sptr2 = bsptr2;
}

static tuple1_t tuple;

static intern_t vars[1];

#warning find a better way to handle errors ?
unsigned int mira_errno = MIRA_NO_ERROR;

#define check(x) \
    do { \
        if(!(x)) \
            return 0; \
    } while(0)

static inline void tuple_reset() {
    tuple.ptr = 0;
}

static int tuple_push(intern_t v) {
    if(tuple.ptr >= ARRAY_SIZE(tuple.data)) {
        mira_errno = MIRA_TUPLE_OVERFLOW;
        return 0;
    }
    tuple.data[tuple.ptr++] = v;
    return 1;
}

#define stack_push_fn(n) \
    static int stack##n##_push() { \
        assert(tuple.ptr <= ARRAY_SIZE(stack##n[0].data)); \
        if(sptr##n >= MIRA_STACK_SIZE) { \
            mira_errno = MIRA_STACK_OVERFLOW; \
            return 0; \
        } \
        for(size_t i = 0; i < tuple.ptr; i++) \
            stack##n[sptr##n].data[i] = tuple.data[i]; \
        stack##n[sptr##n].ptr = tuple.ptr; \
        sptr##n++; \
        return 1; \
    }

stack_push_fn(0)
stack_push_fn(1)
stack_push_fn(2)

#define stack_peek_fn(n) \
    static int stack##n##_peek() { \
        if(sptr##n == 0) { \
            mira_errno = MIRA_STACK_UNDERFLOW; \
            return 0; \
        } \
        for(size_t i = 0; i < sptr##n; i++) \
            tuple.data[i] = stack##n[sptr##n - 1].data[i]; \
        tuple.ptr = stack##n[sptr##n - 1].ptr; \
        return 1; \
    }

stack_peek_fn(0)
stack_peek_fn(1)
stack_peek_fn(2)

#define stack_pop_fn(n) \
    static int stack##n##_pop() { \
        check(stack##n##_peek()); \
        sptr##n--; \
        return 1; \
    }

stack_pop_fn(0)
stack_pop_fn(1)
stack_pop_fn(2)

int init() {
    tuple_reset();
    check(tuple_push(1));
    check(stack0_push());

    tuple_reset();
    check(tuple_push(2));
    check(stack0_push());

    tuple_reset();
    check(tuple_push(3));
    check(stack0_push());

    tuple_reset();
    check(tuple_push(4));
    check(stack0_push());

    tuple_reset();
    check(tuple_push(5));
    check(stack0_push());

    tuple_reset();
    check(tuple_push(0));
    check(stack1_push());
    return 1;
}

#include <stdio.h>

#define check_fail(x, label) \
    do { \
        if(!(x)) { \
            printf(#x ": check failed\n"); \
            goto label; \
        } \
    } while(0)

#define display_stack(n) \
    do { \
    printf("stack" #n ":\n  "); \
        for(size_t i = 0; i < sptr##n; i++) \
            for(size_t j = 0; j < stack##n[i].ptr; j++) { \
                printf("%d ", stack##n[i].data[j]); \
            } \
        printf("\n"); \
    } while(0)

static int run() {

    rule0:
    printf("rule0 start\n");
    display_stack(0);
    display_stack(2);
    printf("\n");

    save_stack_pointers();
    check_fail(stack1_peek(), rule0_failed);
    if(tuple.ptr != 1) {
        printf("debug1\n");
        goto rule0_failed;
    }
    if(tuple.data[0] != 0) {
        printf("debug2\n");
        goto rule0_failed;
    }
    check_fail(stack0_pop(), rule0_failed);
    if(tuple.ptr != 1) {
        printf("debug3\n");
        goto rule0_failed;
    }
    vars[0] = tuple.data[0];
    printf("vars[0] = %u\n", vars[0]);
    // success
    tuple_reset();
    check(tuple_push(vars[0]));
    check(stack2_push());

    printf("rule0 success\n");
    display_stack(0);
    display_stack(2);
    printf("\n");

    goto rule0;

    rule0_failed:
    printf("fail\n");
    restore_stack_pointers();

    rule1:
    printf("rule1\n");
    save_stack_pointers();
    check_fail(stack1_pop(), rule1_failed);
    if(tuple.ptr != 1)
        goto rule1_failed;
    if(tuple.data[0] != 0)
        goto rule1_failed;
    goto rule0;

    rule1_failed:
    printf("fail\n");
    restore_stack_pointers();
}



#endif

#ifdef MIRA_GENERATE_MAIN

int main(void) {
    init();
    run();
    printf("::\n");
    for(size_t i = 0; i < sptr0; i++) {
        for(size_t j = 0; j < stack0[i].ptr; j++) {
            printf("%d ", stack0[i].data[j]);
        }
        printf("\n");
    }

    printf("\n");

    printf(":dst:\n");
    for(size_t i = 0; i < sptr2; i++) {
        for(size_t j = 0; j < stack2[i].ptr; j++) {
            printf("%d ", stack2[i].data[j]);
        }
        printf("\n");
    }
    printf("\n");

}

#endif
#endif