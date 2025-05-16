const std = @import("std");
const rl = @import("raylib");

const WINDOW_WIDTH = 1080;
const WINDOW_HEIGHT = 720;

var camera = rl.Camera2D{
    .offset = .{ .x = WINDOW_WIDTH / 2, .y = WINDOW_HEIGHT / 2 },
    .target = .{ .x = WINDOW_WIDTH / 2, .y = WINDOW_HEIGHT / 2 },
    .rotation = 0,
    .zoom = 1,
};

var og_tx: ?rl.Texture = null;
var ero_tx: ?rl.Texture = null;
var dila_tx: ?rl.Texture = null;
var grad_tx: ?rl.Texture = null;

const mascara = [_]u8{ 0, 1, 0, 1, 1, 1, 0, 1, 0 };

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Filtro laplaciano");
    defer {
        if (og_tx) |_| {
            rl.unloadTexture(og_tx.?);
            rl.unloadTexture(ero_tx.?);
            rl.unloadTexture(dila_tx.?);
            rl.unloadTexture(grad_tx.?);
        }
        rl.closeWindow();
    }

    while (!rl.windowShouldClose()) {
        if (rl.isFileDropped()) {
            if (og_tx) |_| {
                rl.unloadTexture(og_tx.?);
                rl.unloadTexture(ero_tx.?);
                rl.unloadTexture(dila_tx.?);
                rl.unloadTexture(grad_tx.?);
            }
            const files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(files);

            if (files.count > 1) {
                std.debug.print("Err: Número de errado de arquivos", .{});
            } else {
                og_tx = try rl.loadTexture(std.mem.span(files.paths[0]));

                const og = try rl.loadImageFromTexture(og_tx.?);

                var cinza = rl.imageCopy(og);
                // defer rl.unloadImage(cinza);
                grayscale(&cinza);

                const ero = erosao(cinza, &mascara);
                const dila = dilatacao(cinza, &mascara);
                const grad = gradiente(cinza, &mascara);

                ero_tx = try rl.loadTextureFromImage(ero);
                dila_tx = try rl.loadTextureFromImage(dila);
                grad_tx = try rl.loadTextureFromImage(grad);
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

            // Erosão
            rl.drawText("Erosão", 1 * (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(ero_tx.?, 1 * (og_tx.?.width + 64), 64, .white);

            // Dilatação
            rl.drawText("Dilatação", 2 * (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(dila_tx.?, 2 * (og_tx.?.width + 64), 64, .white);

            // Gradiente morfológico
            rl.drawText("Gradiente morfológico", og_tx.?.width + 64, og_tx.?.height + 68, 32, .black);
            rl.drawTexture(grad_tx.?, 1 * (og_tx.?.width + 64), og_tx.?.height + 128, .white);
        } else {
            rl.drawText("Arraste uma imagem aqui para começar", 4, 4, 32, .black);
        }
        rl.endMode2D();
    }
}

fn grayscale(img: *rl.Image) void {
    const og_format = img.format;
    const cores = rl.loadImageColors(img.*) catch unreachable;
    for (cores) |*cor| {
        cor.*.r = @intCast((@as(usize, @intCast(cor.*.r)) +
            @as(usize, @intCast(cor.*.g)) +
            @as(usize, @intCast(cor.*.b))) / 3);
        cor.*.g = cor.*.r;
        cor.*.b = cor.*.r;
    }
    img.data = cores.ptr;
    img.format = .uncompressed_r8g8b8a8;
    rl.imageFormat(img, og_format);
}

fn erosao(img: rl.Image, mask: []const u8) rl.Image {
    var nova = rl.imageCopy(img);
    var novo_cor = rl.loadImageColors(nova) catch unreachable;
    const og_cor = rl.loadImageColors(img) catch unreachable;

    const width: usize = @intCast(img.width);
    const height: usize = @intCast(img.height);
    for (1..width - 1) |i| {
        for (1..height - 1) |j| {
            const cor = blk: {
                var menor: u8 = 255;
                if (og_cor[i - 1 + (j - 1) * width].r < menor and mask[0] == 1) {
                    menor = og_cor[i - 1 + (j - 1) * width].r;
                }
                if (og_cor[i + (j - 1) * width].r < menor and mask[1] == 1) {
                    menor = og_cor[i + (j - 1) * width].r;
                }
                if (og_cor[i + 1 + (j - 1) * width].r < menor and mask[2] == 1) {
                    menor = og_cor[i + 1 + (j - 1) * width].r;
                }
                if (og_cor[i - 1 + (j) * width].r < menor and mask[3] == 1) {
                    menor = og_cor[i - 1 + (j) * width].r;
                }
                if (og_cor[i + (j) * width].r < menor and mask[4] == 1) {
                    menor = og_cor[i + (j) * width].r;
                }
                if (og_cor[i + 1 + (j) * width].r < menor and mask[5] == 1) {
                    menor = og_cor[i + 1 + (j) * width].r;
                }
                if (og_cor[i - 1 + (j + 1) * width].r < menor and mask[6] == 1) {
                    menor = og_cor[i + (j + 1) * width].r;
                }
                if (og_cor[i + (j + 1) * width].r < menor and mask[7] == 1) {
                    menor = og_cor[i + (j + 1) * width].r;
                }
                if (og_cor[i + 1 + (j + 1) * width].r < menor and mask[8] == 1) {
                    menor = og_cor[i + 1 + (j + 1) * width].r;
                }
                break :blk menor;
            };
            novo_cor[i + j * width].r = cor;
            novo_cor[i + j * width].g = cor;
            novo_cor[i + j * width].b = cor;
            novo_cor[i + j * width].a = 255;
        }
    }
    nova.data = novo_cor.ptr;
    nova.format = .uncompressed_r8g8b8a8;

    return nova;
}

fn dilatacao(img: rl.Image, mask: []const u8) rl.Image {
    var nova = rl.imageCopy(img);
    var novo_cor = rl.loadImageColors(nova) catch unreachable;
    const og_cor = rl.loadImageColors(img) catch unreachable;

    const width: usize = @intCast(img.width);
    const height: usize = @intCast(img.height);
    for (1..width - 1) |i| {
        for (1..height - 1) |j| {
            const cor = blk: {
                var maior: u8 = 0;
                if (og_cor[i - 1 + (j - 1) * width].r > maior and mask[0] == 1) {
                    maior = og_cor[i - 1 + (j - 1) * width].r;
                }
                if (og_cor[i + (j - 1) * width].r > maior and mask[1] == 1) {
                    maior = og_cor[i + (j - 1) * width].r;
                }
                if (og_cor[i + 1 + (j - 1) * width].r > maior and mask[2] == 1) {
                    maior = og_cor[i + 1 + (j - 1) * width].r;
                }
                if (og_cor[i - 1 + (j) * width].r > maior and mask[3] == 1) {
                    maior = og_cor[i - 1 + (j) * width].r;
                }
                if (og_cor[i + (j) * width].r > maior and mask[4] == 1) {
                    maior = og_cor[i + (j) * width].r;
                }
                if (og_cor[i + 1 + (j) * width].r > maior and mask[5] == 1) {
                    maior = og_cor[i + 1 + (j) * width].r;
                }
                if (og_cor[i - 1 + (j + 1) * width].r > maior and mask[6] == 1) {
                    maior = og_cor[i + (j + 1) * width].r;
                }
                if (og_cor[i + (j + 1) * width].r > maior and mask[7] == 1) {
                    maior = og_cor[i + (j + 1) * width].r;
                }
                if (og_cor[i + 1 + (j + 1) * width].r > maior and mask[8] == 1) {
                    maior = og_cor[i + 1 + (j + 1) * width].r;
                }
                break :blk maior;
            };
            novo_cor[i + j * width].r = cor;
            novo_cor[i + j * width].g = cor;
            novo_cor[i + j * width].b = cor;
            novo_cor[i + j * width].a = 255;
        }
    }
    nova.data = novo_cor.ptr;
    nova.format = .uncompressed_r8g8b8a8;

    return nova;
}

fn gradiente(img: rl.Image, mask: []const u8) rl.Image {
    var nova = rl.imageCopy(img);
    const ero = erosao(img, mask);
    defer rl.unloadImage(ero);

    const dila = dilatacao(img, mask);
    defer rl.unloadImage(dila);

    const novo_cor = rl.loadImageColors(nova) catch unreachable;
    const ero_cor = rl.loadImageColors(ero) catch unreachable;
    const dila_cor = rl.loadImageColors(dila) catch unreachable;

    for (novo_cor, dila_cor, ero_cor) |*i, j, k| {
        i.*.r = j.r - k.r;
        i.*.g = i.*.r;
        i.*.b = i.*.r;
    }
    nova.data = novo_cor.ptr;
    nova.format = .uncompressed_r8g8b8a8;

    return nova;
}
