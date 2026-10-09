#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void sleep_ms(long milliseconds) {
    struct timespec delay = {.tv_sec = milliseconds / 1000,
                             .tv_nsec = (milliseconds % 1000) * 1000000L};
    while (nanosleep(&delay, &delay) == -1 && errno == EINTR) {}
}

static long env_long(const char *name, long minimum, long maximum) {
    const char *text = getenv(name);
    char *end = NULL;
    if (text == NULL || *text == '\0') {
        fprintf(stderr, "missing environment variable: %s\n", name);
        exit(2);
    }
    errno = 0;
    long value = strtol(text, &end, 10);
    if (errno != 0 || *end != '\0' || value < minimum || value > maximum) {
        fprintf(stderr, "invalid %s\n", name);
        exit(2);
    }
    return value;
}

static int memory_case(void) {
    const long limit_mb = env_long("MEMORY_LIMIT", 50, 512);
    const size_t chunk_size = 4U * 1024U * 1024U;
    void **chunks = calloc((size_t)limit_mb / 4U + 2U, sizeof(*chunks));
    if (chunks == NULL) return 2;
    long allocated = 0;
    puts("SYNTHETIC memory allocation started");
    fflush(stdout);
    while (allocated < limit_mb) {
        void *chunk = malloc(chunk_size);
        if (chunk == NULL) return 2;
        memset(chunk, 0x5a, chunk_size);
        chunks[allocated / 4] = chunk;
        allocated += 4;
        printf("MEMORY_SAMPLE allocated_mb=%ld\n", allocated);
        fflush(stdout);
        sleep_ms(200);
    }
    printf("Memory limit exceeded: synthetic allocation reached %ld MB\n", limit_mb);
    puts("SELF-TERMINATED: application MemoryGuard policy (not kernel OOM)");
    fflush(stdout);
    return 42;
}

static volatile sig_atomic_t cpu_stop = 0;
static void stop_cpu(int signal_number) {
    (void)signal_number;
    cpu_stop = 1;
}

static int cpu_case(void) {
    const long threshold = env_long("CPU_MAX_OCCUPY", 10, 100);
    signal(SIGTERM, stop_cpu);
    const clock_t start_cpu = clock();
    struct timespec start_wall;
    clock_gettime(CLOCK_MONOTONIC, &start_wall);
    uint64_t value = 1;
    while (!cpu_stop) {
        for (unsigned i = 0; i < 1000000U; ++i) value = value * 6364136223846793005ULL + 1U;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        const double wall = (double)(now.tv_sec - start_wall.tv_sec) +
                            (double)(now.tv_nsec - start_wall.tv_nsec) / 1000000000.0;
        const double cpu = 100.0 * (double)(clock() - start_cpu) / (double)CLOCKS_PER_SEC / wall;
        if (wall >= 1.0 && threshold < 100 && cpu > (double)threshold) {
            printf("WATCHDOG threshold exceeded measured=%.1f limit=%ld\n", cpu, threshold);
            puts("WATCHDOG: sending SIGTERM to synthetic worker");
            fflush(stdout);
            raise(SIGTERM);
        }
        if (wall >= 3.0) break;
    }
    if (cpu_stop) {
        puts("WATCHDOG SIGTERM observed; application stopped by policy");
        return 43;
    }
    printf("CPU_CONTROL_COMPLETED value=%llu\n", (unsigned long long)value);
    return 0;
}

static pthread_mutex_t lock_a = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t lock_b = PTHREAD_MUTEX_INITIALIZER;
static pthread_barrier_t barrier;

struct lock_order { pthread_mutex_t *first; pthread_mutex_t *second; const char *name; };

static void *lock_worker(void *argument) {
    struct lock_order *order = argument;
    pthread_mutex_lock(order->first);
    printf("%s acquired first lock\n", order->name);
    fflush(stdout);
    pthread_barrier_wait(&barrier);
    printf("%s WAITING BLOCKED on peer lock\n", order->name);
    fflush(stdout);
    pthread_mutex_lock(order->second);
    pthread_mutex_unlock(order->second);
    pthread_mutex_unlock(order->first);
    return NULL;
}

static int deadlock_case(void) {
    const char *enabled = getenv("MULTI_THREAD_ENABLE");
    if (enabled == NULL) return 2;
    if (strcmp(enabled, "false") == 0 || strcmp(enabled, "0") == 0 || strcmp(enabled, "no") == 0) {
        puts("SINGLE_THREAD_CONTROL_COMPLETED without circular wait");
        return 0;
    }
    if (strcmp(enabled, "true") != 0 && strcmp(enabled, "1") != 0 && strcmp(enabled, "yes") != 0) return 2;
    pthread_t first_thread, second_thread;
    struct lock_order first = {&lock_a, &lock_b, "Thread-A"};
    struct lock_order second = {&lock_b, &lock_a, "Thread-B"};
    pthread_barrier_init(&barrier, NULL, 2);
    if (pthread_create(&first_thread, NULL, lock_worker, &first) != 0 ||
        pthread_create(&second_thread, NULL, lock_worker, &second) != 0) return 2;
    pthread_join(first_thread, NULL);
    pthread_join(second_thread, NULL);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (strcmp(argv[1], "memory") == 0) return memory_case();
    if (strcmp(argv[1], "cpu") == 0) return cpu_case();
    if (strcmp(argv[1], "deadlock") == 0) return deadlock_case();
    return 2;
}
