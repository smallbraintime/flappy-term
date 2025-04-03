const std = @import("std");
const at = @import("asciitecture");

const bird =
    \\╭───╮
    \\│  ^│>
    \\╰───╯
;

const pipe_bottom =
    \\╭──────╮
    \\│      │
    \\│      │
    \\│      │
    \\│      │
    \\│      │
;

const pipe_top =
    \\│      │
    \\│      │
    \\│      │
    \\│      │
    \\│      │
    \\│      │
    \\╰──────╯
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("memory leak occured");

    var term = try at.Terminal(at.LinuxTty).init(gpa.allocator(), 60, null);
    defer term.deinit() catch unreachable;
    term.setBg(at.style.IndexedColor.black);

    var painter = term.painter();

    var input = try at.input.Input.init();
    defer input.deinit() catch unreachable;

    const bird_sprite = at.sprite.Sprite.init(bird, .{ .fg = at.style.IndexedColor.red });

    const pipe_top_sprite = at.sprite.Sprite.init(pipe_top, .{ .fg = at.style.IndexedColor.yellow });
    const pipe_bottom_sprite = at.sprite.Sprite.init(pipe_bottom, .{ .fg = at.style.IndexedColor.yellow });

    const width: f32 = @floatFromInt(term._win_size.width);

    var bird_pos: at.math.Vec2 = at.math.vec2(-width, 0);
    const velocityx: f32 = 10.0;
    const velocityy: f32 = 20.0;
    var jumping = false;
    var counter: f32 = 0;

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

        bird_pos = bird_pos.add(&at.math.vec2(velocityx * term.delta_time, velocityy * term.delta_time));

        var i: f32 = -width;
        while (i <= width) : (i += 30) {
            try pipe_bottom_sprite.draw(&painter, &at.math.vec2(i, 10));
            try pipe_top_sprite.draw(&painter, &at.math.vec2(i, -10));
        }

        try bird_sprite.draw(&painter, &bird_pos);

        try term.draw();
    }
}
