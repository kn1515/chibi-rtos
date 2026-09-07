#include <inttypes.h>
#include <stdio.h>
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mini_os.h"

int64_t os_now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static uint32_t task_a(void *arg)
{
    unsigned *counter = arg;
    printf("[%" PRId64 " ms] A: %u\n", os_now_ms(), ++*counter);
    return 500;  // 処理終了後、500ms待つ
}

static uint32_t task_b(void *arg)
{
    unsigned *counter = arg;
    printf("[%" PRId64 " ms] B: %u\n", os_now_ms(), ++*counter);
    return 1000;
}

void app_main(void)
{
    static unsigned a_count;
    static unsigned b_count;
    os_init();

    // assert内部に登録処理を入れない（assert無効時にも実行する）。
    bool a_ok = os_add_task(task_a, &a_count);
    bool b_ok = os_add_task(task_b, &b_count);
    if (!a_ok || !b_ok) {
        printf("Task registration failed\n");
        return;
    }

    printf("mini_os: cooperative scheduler on ESP-IDF\n");
    for (;;) {
        os_step();
        // 下層FreeRTOSのIdleタスク等にも実行時間を渡す。
        vTaskDelay(1);
    }
}
