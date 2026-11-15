#include "REPLInputSupport.h"
#include <errno.h>
#include <unistd.h>

/* Pinned Bestline C API; use its supported I/O hook, not a library fork. */
extern void bestlineUserIO(int (*)(int, void *, int),
                          int (*)(int, const void *, int), int (*)(int, int, int));

static int interrupted;

/* Runs only on the serialized terminal worker, never as a signal handler. A
   negative read makes Bestline restore terminal state and discard partial input;
   zero would submit a nonempty buffer and is deliberately not used. */
static int read_with_interrupt(int fd, void *buffer, int count) {
    int result = (int)read(fd, buffer, (size_t)count);
    if (result > 0) {
        unsigned char *bytes = buffer;
        for (int index = 0; index < result; ++index) {
            if (bytes[index] == 3) {
                interrupted = 1;
                errno = ECANCELED;
                return -1;
            }
        }
    }
    return result;
}

int timebox_repl_install_input_hook(void) {
    interrupted = 0;
    bestlineUserIO(read_with_interrupt, 0, 0);
    return 0;
}

int timebox_repl_remove_input_hook(void) {
    bestlineUserIO(0, 0, 0);
    return interrupted;
}
