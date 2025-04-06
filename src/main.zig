const std = @import("std");
const at = @import("asciitecture");

const SCREEN_WIDTH = 105.0;
const SCREEN_HEIGHT = 35.0;
const PIPE_WIDTH = 5.0;
const PIPE_HEIGHT = 200.0;
const PIPE_SPACE = 15.0;
const PIPE_OFFSET = 20;
const SCREEN_BOTTOM = SCREEN_HEIGHT / 2.0;
const SCREEN_RIGHT = SCREEN_WIDTH / 2.0;
const VELOCITYX = 5.0;
const VELOCITYY = 15.0;
const BIRD =
    \\╭───╮
    \\│  ^│>
    \\╰─V─╯
;

const PipeSegment = struct {
    bottom: at.math.Rectangle,
    top: at.math.Rectangle,
    visited: bool = false,

    pub fn init(xpos: f32) PipeSegment {
        var rn: [1]u8 = undefined;
        std.posix.getrandom(&rn) catch unreachable;
        var rng = std.rand.DefaultPrng.init(@intCast(rn[0]));

        const yoffset: f32 = @floatFromInt(rng.random().intRangeAtMost(
            i32,
            @intFromFloat(SCREEN_BOTTOM - SCREEN_HEIGHT + PIPE_SPACE + 1),
            @intFromFloat(SCREEN_BOTTOM - 1),
        ));

        const bottom = at.math.Rectangle.init(
            at.math.vec2(xpos, yoffset),
            PIPE_WIDTH,
            PIPE_HEIGHT,
        );

        const top = at.math.Rectangle.init(
            bottom.pos.sub(&at.math.vec2(0, PIPE_SPACE + PIPE_HEIGHT)),
            PIPE_WIDTH,
            PIPE_HEIGHT,
        );

        return .{
            .bottom = bottom,
            .top = top,
        };
    }
};

pub const GameState = struct {
    bird_collider: at.math.Rectangle,
    pipe_segments: std.ArrayListUnmanaged(PipeSegment),
    jumping: bool = false,
    result: usize = 0,
    lost: bool = false,
    time_elapsed: f32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        bird_width: f32,
        bird_height: f32,
    ) !GameState {
        const bird_collider = at.math.Rectangle.init(
            at.math.vec2(0, 0),
            bird_width,
            bird_height,
        );

        var pipe_segments = try std.ArrayListUnmanaged(PipeSegment).initCapacity(
            allocator,
            PIPE_OFFSET,
        );
        errdefer pipe_segments.deinit(allocator);
        for (0..PIPE_OFFSET) |i| {
            pipe_segments.appendAssumeCapacity(PipeSegment.init(
                SCREEN_RIGHT + @as(f32, @floatFromInt(i * PIPE_OFFSET)),
            ));
        }

        return .{
            .bird_collider = bird_collider,
            .pipe_segments = pipe_segments,
        };
    }

    pub fn deinit(self: *GameState, allocator: std.mem.Allocator) void {
        self.pipe_segments.deinit(allocator);
    }

    pub fn update(
        self: *GameState,
        allocator: std.mem.Allocator,
        input: *at.input.Input,
        delta_time: f32,
    ) !void {
        if (self.lost) return;

        if (input.contains(.space) and !self.jumping) self.jumping = true;

        if (self.jumping) {
            self.bird_collider.pos = self.bird_collider.pos.sub(&at.math.vec2(
                0,
                VELOCITYY * 2 * delta_time,
            ));
            self.time_elapsed += delta_time;

            if (self.time_elapsed >= 0.5) {
                self.jumping = false;
                self.time_elapsed = 0;
            }
        }

        self.bird_collider.pos = self.bird_collider.pos.add(&at.math.vec2(
            0,
            VELOCITYY * delta_time,
        ));

        for (self.pipe_segments.items) |*item| {
            item.top.pos = item.top.pos.sub(&at.math.vec2(VELOCITYX * delta_time, 0));
            item.bottom.pos = item.bottom.pos.sub(&at.math.vec2(VELOCITYX * delta_time, 0));

            if (self.bird_collider.collidesWith(&.{ .rectangle = item.top }) or
                self.bird_collider.collidesWith(&.{ .rectangle = item.bottom }))
            {
                self.lost = true;
            }

            if (item.top.pos.x() + PIPE_WIDTH < 0 and !item.visited) {
                item.visited = true;
                self.result += 1;
            }
        }

        if (self.pipe_segments.items[0].top.pos.x() + PIPE_WIDTH < -SCREEN_RIGHT) {
            _ = self.pipe_segments.orderedRemove(0);
        }

        if (self.pipe_segments.getLast().top.pos.x() < SCREEN_RIGHT) {
            try self.pipe_segments.append(allocator, PipeSegment.init(
                self.pipe_segments.getLast().top.pos.x() +
                    @as(f32, @floatFromInt(PIPE_OFFSET)),
            ));
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("memory leak occured");

    var term = try at.Terminal(at.LinuxTty).init(
        gpa.allocator(),
        60,
        .{ .width = SCREEN_WIDTH, .height = SCREEN_HEIGHT },
    );
    defer term.deinit() catch unreachable;
    term.setBg(at.style.IndexedColor.bright_blue);

    var painter = term.painter();

    var input = try at.input.Input.init();
    defer input.deinit() catch unreachable;

    const bird_sprite = at.sprite.Sprite.init(
        BIRD,
        .{ .fg = at.style.IndexedColor.yellow },
    );

    const paragraph_config = at.widgets.Paragraph.ParagraphConfig{
        .border_style = .{
            .border = .rounded,
            .style = .{
                .fg = at.style.IndexedColor.white,
                .attr = .bold,
            },
        },
        .text_style = .{
            .fg = at.style.IndexedColor.white,
            .attr = .bold,
        },
        .filling = true,
        .animation = .{
            .speed = 5,
            .looping = true,
        },
    };
    var game_over_popup = try at.widgets.Paragraph.init(
        gpa.allocator(),
        &[_][]const u8{ "GAME OVER", " [space] " },
        paragraph_config,
    );
    defer game_over_popup.deinit();

    const bird_dims = try bird_sprite.dims();

    blk: while (true) {
        var game_state = try GameState.init(
            gpa.allocator(),
            @floatFromInt(bird_dims.width),
            @floatFromInt(bird_dims.height),
        );
        defer game_state.deinit(gpa.allocator());

        while (true) {
            if (input.contains(.escape)) break :blk;

            if (!game_state.lost) {
                try game_state.update(gpa.allocator(), &input, term.delta_time);
            }

            painter.setCell(&.{ .bg = at.style.IndexedColor.green });
            for (game_state.pipe_segments.items) |*item| {
                painter.drawRectangleShape(&item.bottom, true);
                painter.drawRectangleShape(&item.top, true);
            }

            try bird_sprite.draw(&painter, &game_state.bird_collider.pos);

            painter.setDrawingSpace(.screen);
            painter.setCell(&.{
                .fg = at.style.IndexedColor.white,
                .bg = at.style.IndexedColor.black,
            });
            var buf: [5]u8 = undefined;
            const fps = try std.fmt.bufPrint(&buf, "{}", .{game_state.result});
            try painter.drawText(fps, &at.math.vec2(0, -SCREEN_BOTTOM));
            painter.setDrawingSpace(.world);

            if (game_state.lost) {
                try game_over_popup.draw(
                    &painter,
                    &at.math.vec2(0, 0),
                    term.delta_time,
                );
                if (input.contains(.space)) break;
            }

            try term.draw();
        }
    }
}
