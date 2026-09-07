#ifndef MINI_OS_H
#define MINI_OS_H

#include <stdbool.h>
#include <stdint.h>

#define OS_MAX_TASKS 4

// タスクは短い処理をし、次回までの待ち時間(ms)を返す。
typedef uint32_t (*os_task_fn)(void *arg);

// ハードウェア側で実装する単調増加の時計。
int64_t os_now_ms(void);
void os_init(void);
bool os_add_task(os_task_fn fn, void *arg);
bool os_step(void);

#endif
