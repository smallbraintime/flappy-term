const std = @import("std");
const at = @import("asciitecture");

const bird =
    \\╭───╮
    \\│  ^│>
    \\╰─V─╯
;

const PipeSegment = struct {
    bottom: at.math.Rectangle,
    top: at.math.Rectangle,
    visited: bool = false,

    pub fn init(xpos: f32, screen_bottom: f32) PipeSegment {
        var rn: [1]u8 = undefined;
        std.posix.getrandom(&rn) catch unreachable;
        var rng = std.rand.DefaultPrng.init(@intCast(rn[0]));
        const yoffset: f32 = @floatFromInt(rng.random().intRangeAtMost(u8, 2, 10));
        const y = 35 / yoffset;

        var pipe_segment: PipeSegment = undefined;

        pipe_segment.bottom = at.math.Rectangle.init(
            at.math.vec2(xpos, screen_bottom - y),
            @floatFromInt(5),
            @floatFromInt(20),
        );

        pipe_segment.top = at.math.Rectangle.init(
            pipe_segment.bottom.pos.sub(&at.math.vec2(0, 15 + 20)),
            @floatFromInt(5),
            @floatFromInt(20),
        );

        return pipe_segment;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("memory leak occured");

    var term = try at.Terminal(at.LinuxTty).init(gpa.allocator(), 60, .{ .width = 105, .height = 35 });
    defer term.deinit() catch unreachable;
    term.setBg(at.style.IndexedColor.bright_blue);

    var painter = term.painter();

    var input = try at.input.Input.init();
    defer input.deinit() catch unreachable;

    const bird_sprite = at.sprite.Sprite.init(bird, .{ .fg = at.style.IndexedColor.yellow, .bg = at.style.IndexedColor.bright_magenta });

    var bird_pos: at.math.Vec2 = at.math.vec2(0, 0);
    const velocityx: f32 = 10.0;
    const velocityy: f32 = 15.0;
    var jumping = false;
    var counter: f32 = 0;
    var pipesx: f32 = 0;
    const bird_dims = try bird_sprite.dims();
    var bird_collider = at.math.Rectangle.init(at.math.vec2(0, 0), @floatFromInt(bird_dims.width), @floatFromInt(bird_dims.height));
    var result: usize = 0;

    var pipes = try std.ArrayList(PipeSegment).initCapacity(gpa.allocator(), term._win_size.width / 20);
    defer pipes.deinit();
    const screen_bottom = 35 / 2;
    const screen_right = 105 / 2;
    for (0..20) |i| {
        try pipes.append(PipeSegment.init(
            screen_right + @as(f32, @floatFromInt(i)) * 20,
            screen_bottom,
        ));
    }
    // blk:
    while (true) {
        if (input.contains(.escape)) break;
        if (input.contains(.space) and !jumping) jumping = true;

        if (jumping) {
            bird_pos = bird_pos.sub(&at.math.vec2(0, velocityy * 2 * term.delta_time));
            counter += term.delta_time;
            if (counter >= 0.5) {
                jumping = false;
                counter = 0;
            }
        }

        bird_pos = bird_pos.add(&at.math.vec2(0, velocityy * term.delta_time));
        bird_collider.pos = bird_pos;
        pipesx -= velocityx * term.delta_time;

        for (pipes.items) |*item| {
            item.top.pos = item.top.pos.sub(&at.math.vec2(5 * term.delta_time, 0));
            item.bottom.pos = item.bottom.pos.sub(&at.math.vec2(5 * term.delta_time, 0));
            painter.setCell(&.{ .bg = at.style.IndexedColor.green });
            painter.drawRectangleShape(&item.bottom, false);
            painter.drawRectangleShape(&item.top, false);
            if (bird_collider.collidesWith(&.{ .rectangle = item.top }) or bird_collider.collidesWith(&.{ .rectangle = item.bottom })) {
                try painter.drawText("GAME OVER", &at.math.vec2(0, 0));
                // try term.draw();
                // while (true) {
                //     if (input.contains(.space)) break :blk;
                // }
            }

            if (item.top.pos.x() < 0 and !item.visited) {
                item.visited = true;
                result += 1;
            }
        }

        if (pipes.items[0].top.pos.x() < -screen_right) {
            _ = pipes.orderedRemove(0);
        }

        if (pipes.getLast().top.pos.x() < screen_right) {
            try pipes.append(PipeSegment.init(
                pipes.getLast().top.pos.x() + 20,
                screen_bottom,
            ));
        }

        try bird_sprite.draw(&painter, &bird_pos);

        painter.setDrawingSpace(.screen);
        painter.setCell(&.{ .fg = at.style.IndexedColor.white, .bg = at.style.IndexedColor.black });
        var buf: [5]u8 = undefined;
        const fps = try std.fmt.bufPrint(&buf, "{}", .{result});
        try painter.drawText(fps, &(at.math.vec2((105 / 2) - 4, -35 / 2 - 0.5)));
        painter.setDrawingSpace(.world);

        try term.draw();
    }
}
