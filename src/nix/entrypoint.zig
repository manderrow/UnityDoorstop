const builtin = @import("builtin");

const root = @import("../root.zig");

fn doorstop_ctor() callconv(.c) void {
    if (builtin.is_test)
        return;

    root.logger.info("Injecting", .{});

    root.config.load();

    if (!root.config.c.enabled) {
        root.logger.info("Doorstop not enabled! Skipping!", .{});
        return;
    }

    root.hooks.installHooksNix();
}

export const init_array linksection(if (builtin.os.tag == .macos) "__DATA,__mod_init_func" else ".init_array") = [1]*const fn () callconv(.C) void{doorstop_ctor};
