const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const godot_path = b.option([]const u8, "godot", "Path to Godot engine binary [default: `godot`]") orelse "godot";

    const precision = b.option([]const u8, "precision", "Floating point precision, either `float` or `double` [default: `float`]") orelse "float";
    const arch = b.option([]const u8, "arch", "32") orelse "64";
    const export_path = b.option([]const u8, "output", "Path to save auto-generated files [default: `./gen`]") orelse "./gen";
    const api_path = b.pathJoin(&.{ export_path, "api" });

    const dump_cmd = b.addSystemCommand(&.{
        godot_path, "--dump-extension-api", "--dump-gdextension-interface", "--headless",
    });

    std.fs.cwd().makePath(export_path) catch unreachable;

    dump_cmd.setCwd(.{ .cwd_relative = export_path });
    const dump_step = b.step("dump", "dump api");
    dump_step.dependOn(&dump_cmd.step);

    const binding_generator_step = b.step("binding_generator", "build the binding generator program");
    const binding_generator = b.addExecutable(.{ .name = "binding_generator", .target = target, .optimize = optimize, .root_source_file = b.path(b.pathJoin(&.{ "binding_generator", "main.zig" })), .link_libc = true });
    binding_generator.step.dependOn(dump_step);
    binding_generator.addIncludePath(b.path(export_path));
    binding_generator.addIncludePath(b.path(api_path));
    binding_generator_step.dependOn(&binding_generator.step);
    _ = b.installArtifact(binding_generator);

    const generate_binding = std.Build.Step.Run.create(b, "bind_godot");
    generate_binding.addArtifactArg(binding_generator);
    generate_binding.addArgs(&.{ export_path, api_path, precision, arch });

    const bind_step = b.step("bind", "generate godot bindings");
    bind_step.dependOn(&generate_binding.step);

    const lib = b.addSharedLibrary(.{
        .name = "godot",
        .root_source_file = b.path(b.pathJoin(&.{ "src", "api", "Godot.zig" })),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("godot", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "api", "Godot.zig" })),
        .target = target,
        .optimize = optimize,
    });
    const core_module = b.addModule("GodotCore", .{
        .root_source_file = b.path(b.pathJoin(&.{ api_path, "GodotCore.zig" })),
        .target = target,
        .optimize = optimize,
    });
    core_module.addIncludePath(b.path(export_path));
    core_module.addImport("godot", &lib.root_module);
    lib.root_module.addImport("GodotCore", core_module);

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "precision", precision);
    build_options.addOption([]const u8, "export_path", export_path);
    lib.root_module.addOptions("build_options", build_options);
    lib.addIncludePath(b.path(export_path));
    lib.step.dependOn(bind_step);
    b.installArtifact(lib);
}

pub fn createModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, godot_path: []const u8) *std.Build.Module {
    const precision = b.option([]const u8, "precision", "Floating point precision, either `float` or `double` [default: `float`]") orelse "float";
    const arch = b.option([]const u8, "arch", "32") orelse "64";
    const gen_path = b.option([]const u8, "output", "Path to save auto-generated files [default: `./gen/api`]") orelse "./gen/api";
    const dump_path = b.pathJoin(&.{ thisDirAbs(b.allocator), "src", "api" });

    const dump_cmd = b.addSystemCommand(&.{
        godot_path, "--dump-extension-api", "--dump-gdextension-interface", "--headless",
    });

    std.fs.cwd().makePath(gen_path) catch unreachable;

    dump_cmd.setCwd(.{ .cwd_relative = dump_path });
    const dump_step = b.step("dump", "dump api");
    dump_step.dependOn(&dump_cmd.step);

    const binding_generator = b.addExecutable(.{ .name = "binding_generator", .target = target, .root_source_file = b.path(b.pathJoin(&.{ thisDir(b.allocator), "binding_generator/main.zig" })) });
    binding_generator.addIncludePath(b.path(gen_path));
    binding_generator.addIncludePath(b.path(b.pathJoin(&.{ thisDir(b.allocator), "src", "api" })));
    binding_generator.step.dependOn(dump_step);

    const generate_binding = std.Build.Step.Run.create(b, "bind_godot");
    generate_binding.addArtifactArg(binding_generator);
    generate_binding.addArgs(&.{ dump_path, gen_path, precision, arch });

    const bind_step = b.step("bind", "generate godot bindings");
    bind_step.dependOn(&generate_binding.step);

    const module = b.addModule("godot", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "api", "Godot.zig" })),
        .target = target,
        .optimize = optimize,
    });
    const core_module = b.addModule("GodotCore", .{
        .root_source_file = b.path(b.pathJoin(&.{ gen_path, "GodotCore.zig" })),
        .target = target,
        .optimize = optimize,
    });
    core_module.addIncludePath(b.path(dump_path));
    core_module.addImport("godot", module);
    module.addImport("GodotCore", core_module);

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "precision", precision);
    module.addOptions("build_options", build_options);

    return module;
}

inline fn thisDirAbs(allocator: std.mem.Allocator) []const u8 {
    const abspath = comptime std.fs.path.dirname(@src().file) orelse ".";
    return std.fs.path.relative(allocator, "./", abspath) catch unreachable;
}

inline fn thisDir(allocator: std.mem.Allocator) []const u8 {
    const abspath = thisDirAbs(allocator);
    return std.fs.path.relative(allocator, "./", abspath) catch unreachable;
}
