idf_component_register(SRCS "main.c" "mini_os.c"
                       INCLUDE_DIRS "."
                       REQUIRES esp_timer freertos)
