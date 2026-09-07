#include <assert.h>
#include <stdio.h>
#include "mini_os.h"

static int64_t clock_ms;
int64_t os_now_ms(void) { return clock_ms; }

typedef struct {
    unsigned calls;
    uint32_t delay;
    uint32_t work;
} data_t;

static uint32_t run(void *arg)
{
    data_t *d = arg;
    ++d->calls;
    clock_ms += d->work;
    return d->delay;
}

int main(void)
{
    os_init();
    assert(!os_step());
    assert(!os_add_task(0, 0));
    data_t a = {0, 500, 0}, b = {0, 1000, 0};
    assert(os_add_task(run, &a));
    assert(os_add_task(run, &b));
    assert(os_step() && a.calls == 1);
    assert(os_step() && b.calls == 1);
    assert(!os_step());
    clock_ms = 499;
    assert(!os_step());
    clock_ms = 500;
    assert(os_step() && a.calls == 2);
    assert(!os_step());
    clock_ms = 1000;
    assert(os_step() && b.calls == 2);
    assert(os_step() && a.calls == 3);
    assert(!os_step());

    // 大きく遅れても、過去の分をまとめて実行しない。
    clock_ms = 100000;
    assert(os_step());
    assert(os_step());
    assert(!os_step());
    assert(a.calls == 4 && b.calls == 3);

    // 待ち時間0のタスク同士も登録順に巡回し、独占しない。
    os_init();
    data_t d[OS_MAX_TASKS] = {0};
    for (unsigned i = 0; i < OS_MAX_TASKS; ++i)
        assert(os_add_task(run, &d[i]));
    assert(!os_add_task(run, &a));
    for (unsigned n = 0; n < 12; ++n) {
        unsigned i = n % OS_MAX_TASKS;
        unsigned before = d[i].calls;
        assert(os_step());
        assert(d[i].calls == before + 1);
    }
    for (unsigned i = 0; i < OS_MAX_TASKS; ++i)
        assert(d[i].calls == 3);

    // 待ち時間の起点はコールバックの終了時刻。
    os_init();
    clock_ms = 0;
    data_t slow = {0, 50, 20};
    assert(os_add_task(run, &slow));
    assert(os_step() && clock_ms == 20);
    clock_ms = 69;
    assert(!os_step());
    clock_ms = 70;
    assert(os_step() && slow.calls == 2);
    puts("PASS: deadlines, sleeping, round-robin, capacity, completion-relative delay");
}
