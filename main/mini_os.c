#include "mini_os.h"

typedef struct {
    os_task_fn fn;       // 実行する関数
    void *arg;           // タスクが保持するデータ
    int64_t wake_ms;     // 次回実行できる時刻
} task_t;

static task_t tasks[OS_MAX_TASKS];
static unsigned count;
static unsigned next;

void os_init(void)
{
    count = 0;
    next = 0;
}

bool os_add_task(os_task_fn fn, void *arg)
{
    if (fn == 0 || count == OS_MAX_TASKS) {
        return false;
    }
    tasks[count++] = (task_t){fn, arg, os_now_ms()};
    return true;
}

bool os_step(void)
{
    for (unsigned n = 0; n < count; ++n) {
        unsigned i = (next + n) % count;
        task_t *t = &tasks[i];

        if (os_now_ms() < t->wake_ms) {
            continue;  // まだ待ち時間が終わっていない
        }

        next = (i + 1) % count;
        uint32_t wait_ms = t->fn(t->arg);
        t->wake_ms = os_now_ms() + (int64_t)wait_ms;
        return true;   // 1回の呼び出しで最大1タスクを実行
    }
    return false;      // 全タスク待機中、または未登録
}
