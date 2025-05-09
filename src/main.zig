const std = @import("std");
const rl = @import("raylib");

const WINDOW_WIDTH = 1080;
const WINDOW_HEIGHT = 720;

const LaplaTable = struct {
    m1: isize,
    m2: isize,
    m3: isize,
    m4: isize,
};

var camera = rl.Camera2D{
    .offset = .{ .x = WINDOW_WIDTH / 2, .y = WINDOW_HEIGHT / 2 },
    .target = .{ .x = WINDOW_WIDTH / 2, .y = WINDOW_HEIGHT / 2 },
    .rotation = 0,
    .zoom = 1,
};

var og_tx: ?rl.Texture = null;
var m1_tx: ?rl.Texture = null;
var m2_tx: ?rl.Texture = null;
var m3_tx: ?rl.Texture = null;
var m4_tx: ?rl.Texture = null;

const mask1 = [_]i8{ 0, 1, 0, 1, -4, 1, 0, 1, 0 };
const mask2 = [_]i8{ 1, 1, 1, 1, -8, 1, 1, 1, 1 };
const mask3 = [_]i8{ 0, -1, 0, -1, 4, -1, 0, -1, 0 };
const mask4 = [_]i8{ -1, -1, -1, -1, 8, -1, -1, -1, -1 };

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Filtro laplaciano");
    defer {
        if (og_tx) |_| {
            rl.unloadTexture(og_tx.?);
            rl.unloadTexture(m1_tx.?);
            rl.unloadTexture(m2_tx.?);
            rl.unloadTexture(m3_tx.?);
            rl.unloadTexture(m4_tx.?);
        }
        rl.closeWindow();
    }

    while (!rl.windowShouldClose()) {
        if (rl.isFileDropped()) {
            if (og_tx) |_| {
                rl.unloadTexture(og_tx.?);
                rl.unloadTexture(m1_tx.?);
                rl.unloadTexture(m2_tx.?);
                rl.unloadTexture(m3_tx.?);
                rl.unloadTexture(m4_tx.?);
            }
            const files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(files);

            if (files.count > 1) {
                std.debug.print("Err: Número de errado de arquivos", .{});
            } else {
                og_tx = try rl.loadTexture(std.mem.span(files.paths[0]));

                const og = try rl.loadImageFromTexture(og_tx.?);
                const og_w: usize = @intCast(og.width);
                const og_h: usize = @intCast(og.height);

                // Imagem que será equalizada
                var m1 = rl.imageCopy(og);
                var m1_cor = try rl.loadImageColors(m1);
                grayscale(&m1_cor);

                var m2 = rl.imageCopy(m1);
                var m3 = rl.imageCopy(m1);
                var m4 = rl.imageCopy(m1);

                const m2_cor = try rl.loadImageColors(m2);
                const m3_cor = try rl.loadImageColors(m3);
                const m4_cor = try rl.loadImageColors(m4);

                // Multi vetor para guardar as core * coeficientes
                var lapla = std.MultiArrayList(LaplaTable).empty;
                defer lapla.clearAndFree(allocator);
                try lapla.setCapacity(allocator, m1_cor.len);

                var min = [_]isize{std.math.maxInt(isize)} ** 4;
                var max = [_]isize{std.math.minInt(isize)} ** 4;

                for (0..m1_cor.len) |i| {
                    const h = hood8(i % og_w, i / og_w, m1_cor, og_w, og_h);
                    lapla.appendAssumeCapacity(.{
                        .m1 = applyMask(&h, &mask1),
                        .m2 = applyMask(&h, &mask2),
                        .m3 = applyMask(&h, &mask3),
                        .m4 = applyMask(&h, &mask4),
                    });
                    const l = lapla.get(i);

                    min[0] = if (l.m1 < min[0]) l.m1 else min[0];
                    max[0] = if (l.m1 > max[0]) l.m1 else max[0];
                    min[1] = if (l.m2 < min[1]) l.m2 else min[1];
                    max[1] = if (l.m2 > max[1]) l.m2 else max[1];
                    min[2] = if (l.m3 < min[2]) l.m3 else min[2];
                    max[2] = if (l.m3 > max[2]) l.m3 else max[2];
                    min[3] = if (l.m4 < min[3]) l.m4 else min[3];
                    max[3] = if (l.m4 > max[3]) l.m4 else max[3];
                }

                for (m1_cor, m2_cor, m3_cor, m4_cor, 0..) |*cor1, *cor2, *cor3, *cor4, i| {
                    const l = lapla.get(i);
                    cor1.r = @as(u8, (@intFromFloat(std.math.round(@as(f64, @floatFromInt(l.m1 - min[0])) / @as(f64, @floatFromInt(max[0] - min[0])) * 255))));
                    cor1.g = cor1.r;
                    cor1.b = cor1.r;

                    cor2.r = @as(u8, (@intFromFloat(std.math.round(@as(f64, @floatFromInt(l.m2 - min[1])) / @as(f64, @floatFromInt(max[1] - min[1])) * 255))));
                    cor2.g = cor2.r;
                    cor2.b = cor2.r;

                    cor3.r = @as(u8, (@intFromFloat(std.math.round(@as(f64, @floatFromInt(l.m3 - min[2])) / @as(f64, @floatFromInt(max[2] - min[2])) * 255))));
                    cor3.g = cor3.r;
                    cor3.b = cor3.r;

                    cor4.r = @as(u8, (@intFromFloat(std.math.round(@as(f64, @floatFromInt(l.m4 - min[3])) / @as(f64, @floatFromInt(max[3] - min[3])) * 255))));
                    cor4.g = cor4.r;
                    cor4.b = cor4.r;
                }

                m1.data = m1_cor.ptr;
                m2.data = m2_cor.ptr;
                m3.data = m3_cor.ptr;
                m4.data = m4_cor.ptr;

                m1.format = .uncompressed_r8g8b8a8;
                m2.format = .uncompressed_r8g8b8a8;
                m3.format = .uncompressed_r8g8b8a8;
                m4.format = .uncompressed_r8g8b8a8;

                m1_tx = try rl.loadTextureFromImage(m1);
                m2_tx = try rl.loadTextureFromImage(m2);
                m3_tx = try rl.loadTextureFromImage(m3);
                m4_tx = try rl.loadTextureFromImage(m4);
            }
        }

        if (rl.isMouseButtonDown(.left)) {
            camera.target.x -= rl.getMouseDelta().x * rl.getFrameTime() * 3000.0 * (1 / camera.zoom);
            camera.target.y -= rl.getMouseDelta().y * rl.getFrameTime() * 3000.0 * (1 / camera.zoom);
        }

        if (camera.zoom + rl.getMouseWheelMove() / 10 > 0) {
            camera.zoom += rl.getMouseWheelMove() / 10;
        }

        rl.beginDrawing();
        rl.beginMode2D(camera);
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (og_tx) |_| {
            // Imagem original
            rl.drawText("Imagem original", 4, 4, 32, .black);
            rl.drawTexture(og_tx.?, 0, 64, .white);

            // Laplaciano aplicado nas 4 máscaras
            rl.drawText("Filtro A", 1 * (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(m1_tx.?, 1 * (og_tx.?.width + 64), 64, .white);

            rl.drawText("Filtro B", 2 * (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(m2_tx.?, 2 * (og_tx.?.width + 64), 64, .white);

            rl.drawText("Filtro C", 1 * (og_tx.?.width + 64), og_tx.?.height + 4 + 64, 32, .black);
            rl.drawTexture(m3_tx.?, 1 * (og_tx.?.width + 64), og_tx.?.height + 128, .white);

            rl.drawText("Filtro D", 2 * (og_tx.?.width + 64), og_tx.?.height + 4 + 64, 32, .black);
            rl.drawTexture(m4_tx.?, 2 * (og_tx.?.width + 64), og_tx.?.height + 128, .white);
        } else {
            rl.drawText("Arraste uma imagem aqui para começar", 4, 4, 32, .black);
        }
        rl.endMode2D();
    }
}

fn grayscale(cores: *[]rl.Color) void {
    for (cores.*) |*cor| {
        cor.r = @intCast((@as(usize, @intCast(cor.r)) +
            @as(usize, @intCast(cor.g)) +
            @as(usize, @intCast(cor.b))) / 3);
        cor.g = cor.r;
        cor.b = cor.r;
    }
}

fn hood8(x: usize, y: usize, cores: []rl.Color, width: usize, height: usize) [9]rl.Color {
    const cor = cores[y * width + x];
    const top_left: rl.Color = tl: {
        if (x == 0 or y == 0) {
            break :tl cor;
        } else {
            break :tl cores[y * width + x - width - 1];
        }
    };

    const top_center: rl.Color = tc: {
        if (y == 0) {
            break :tc cor;
        } else {
            break :tc cores[y * width + x - width];
        }
    };

    const top_right: rl.Color = tr: {
        if (x == width - 1 or y == 0) {
            break :tr cor;
        } else {
            break :tr cores[y * width + x - width + 1];
        }
    };

    const center_left: rl.Color = cl: {
        if (x == 0) {
            break :cl cor;
        } else {
            break :cl cores[y * width + x - 1];
        }
    };

    const center_right: rl.Color = cr: {
        if (x == width - 1) {
            break :cr cor;
        } else {
            break :cr cores[y * width + x + 1];
        }
    };

    const bottom_left: rl.Color = bl: {
        if (x == 0 or y == height - 1) {
            break :bl cor;
        } else {
            break :bl cores[y * width + x + width - 1];
        }
    };

    const bottom_center: rl.Color = bc: {
        if (y == height - 1) {
            break :bc cor;
        } else {
            break :bc cores[y * width + x + width];
        }
    };

    const bottom_right: rl.Color = br: {
        if (x == width - 1 or y == height - 1) {
            break :br cor;
        } else {
            break :br cores[y * width + x + width + 1];
        }
    };

    return .{ top_left, top_center, top_right, center_left, cor, center_right, bottom_left, bottom_center, bottom_right };
}

fn applyMask(cores: []const rl.Color, coef: []const i8) isize {
    var acc: isize = 0;
    for (cores, coef) |cor, c| {
        acc += @as(isize, @intCast(cor.r)) * @as(isize, @intCast(c));
    }
    return @divTrunc(acc, 9);
}
