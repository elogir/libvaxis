const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub const panic = vaxis.panic_handler;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(init.io, &buffer);
    const writer = tty.writer();
    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, writer);

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx, .io = init.io, .queue = .{ .io = init.io } };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(writer);
    try vx.queryTerminal(writer, init.io, 1 * std.time.ns_per_s);
    const env = init.environ_map;

    const vt_opts: vaxis.widgets.Terminal.Options = .{
        .winsize = .{
            .rows = 24,
            .cols = 100,
            .x_pixel = 0,
            .y_pixel = 0,
        },
        .scrollback_size = 0,
        .initial_working_directory = env.get("HOME") orelse @panic("no $HOME"),
    };
    const shell = env.get("SHELL") orelse "bash";
    const argv = [_][]const u8{shell};
    var write_buf: [4096]u8 = undefined;
    var vt = try vaxis.widgets.Terminal.init(
        alloc,
        init.io,
        &argv,
        env,
        vt_opts,
        &write_buf,
    );
    defer vt.deinit();
    try vt.spawn();

    var redraw: bool = false;
    while (true) {
        std.Io.sleep(init.io, .fromMilliseconds(8), .awake) catch {};
        // try vt events first
        while (vt.tryEvent()) |event| {
            redraw = true;
            switch (event) {
                .bell => {},
                .title_change => {},
                .exited => return,
                .redraw => {},
                .pwd_change => {},
            }
        }
        while (loop.tryEvent()) |event| {
            redraw = true;
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true })) return;
                    try vt.update(.{ .key_press = key });
                },
                .winsize => |ws| try vx.resize(alloc, writer, ws),
            }
        }
        if (!redraw) continue;
        redraw = false;

        const win = vx.window();
        win.hideCursor();
        win.clear();
        const child = win.child(.{
            .x_off = 4,
            .y_off = 2,
            .width = 120,
            .height = 40,
            .border = .{
                .where = .all,
            },
        });

        try vt.resize(.{
            .rows = child.height,
            .cols = child.width,
            .x_pixel = 0,
            .y_pixel = 0,
        });
        try vt.draw(alloc, child);

        try vx.render(writer);
    }
}
