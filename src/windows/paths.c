#include "paths.h"
#include "../crt.h"
#include "../util/logging.h"

DoorstopPaths *paths_init(void *doorstop_module, bool_t fixed_cwd) {
    char_t *app_path = program_path();
    char_t *app_dir = get_folder_name(app_path);
    char_t *working_dir = get_working_dir();
    char_t *doorstop_path = NULL;
    get_module_path(doorstop_module, &doorstop_path, NULL, 0);

    char_t *doorstop_filename = get_file_name(doorstop_path, FALSE);

    LOG("Doorstop started!");
    LOG("Executable path: %" Ts, app_path);
    LOG("Application dir: %" Ts, app_dir);
    LOG("Working dir: %" Ts, working_dir);
    LOG("Doorstop library path: %" Ts, doorstop_path);
    LOG("Doorstop library name: %" Ts, doorstop_filename);

    if (fixed_cwd) {
        log_warn("Working directory was not the same as app directory, fixed "
                 "it automatically.");
    }

    DoorstopPaths *paths = malloc(sizeof(DoorstopPaths));
    paths->app_path = app_path;
    paths->app_dir = app_dir;
    paths->working_dir = working_dir;
    paths->doorstop_path = doorstop_path;
    paths->doorstop_filename = doorstop_filename;
    return paths;
}

void paths_free(DoorstopPaths *const paths) {
    free(paths->app_path);
    free(paths->app_dir);
    free(paths->working_dir);
    free(paths->doorstop_path);
    free(paths->doorstop_filename);
}
