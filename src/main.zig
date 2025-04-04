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

    const bird_sprite = at.sprite.Sprite.init(bird, .{ .fg = at.style.IndexedColor.yellow });

    var bird_pos: at.math.Vec2 = at.math.vec2(0, 0);
    const velocityx: f32 = 10.0;
    const velocityy: f32 = 15.0;
    var jumping = false;
    var counter: f32 = 0;
    var pipesx: f32 = 0;
    const bird_dims = try bird_sprite.dims();
    var bird_collider = at.math.Rectangle.init(at.math.vec2(0, 0), @floatFromInt(bird_dims.width), @floatFromInt(bird_dims.height));

    var pipes = try std.ArrayList(PipeSegment).initCapacity(gpa.allocator(), term._win_size.width / 20);
    defer pipes.deinit();
    const screen_bottom = 17 / 2;
    const screen_right = 52 / 2;
    for (0..20) |i| {
        var rn: [1]u8 = undefined;
        std.posix.getrandom(&rn) catch unreachable;
        var rng = std.rand.DefaultPrng.init(@intCast(rn[0]));
        const ry: f32 = @floatFromInt(rng.random().intRangeAtMost(u8, 1, 10));
        const y = 17 / ry;
        try pipes.append(PipeSegment{
            .bottom = at.math.Rectangle.init(
                at.math.vec2(screen_right + @as(f32, @floatFromInt(i)) * 20, screen_bottom - y),
                @floatFromInt(5),
                @floatFromInt(20),
            ),
            .top = at.math.Rectangle.init(
                at.math.vec2(screen_right + @as(f32, @floatFromInt(i)) * 20, screen_bottom - y - 37),
                @floatFromInt(5),
                @floatFromInt(20),
            ),
        });
    }

    blk: while (true) {
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
            painter.drawRectangleShape(&item.top, true);
            painter.drawRectangleShape(&item.bottom, true);
            if (bird_collider.collidesWith(&.{ .rectangle = item.top }) or bird_collider.collidesWith(&.{ .rectangle = item.bottom })) {
                try painter.drawText("GAME OVER", &at.math.vec2(0, 0));
                break :blk;
            }
        }

        try bird_sprite.draw(&painter, &bird_pos);

        try term.draw();
    }
}
