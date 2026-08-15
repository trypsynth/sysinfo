const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const exe_module = b.createModule(.{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
	});
	exe_module.linkSystemLibrary("ole32", .{});
	exe_module.linkSystemLibrary("oleaut32", .{});
	exe_module.linkSystemLibrary("advapi32", .{});
	exe_module.linkSystemLibrary("user32", .{});
	exe_module.linkSystemLibrary("gdi32", .{});
	exe_module.linkSystemLibrary("kernel32", .{});
	exe_module.link_libc = true;
	exe_module.addWin32ResourceFile(.{ .file = b.path("src/sysinfo.rc") });

	const exe = b.addExecutable(.{
		.name = "sysinfo",
		.root_module = exe_module,
	});
	exe.subsystem = .windows;

	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);
	run_cmd.step.dependOn(b.getInstallStep());
	const run_step = b.step("run", "Run sysinfo");
	run_step.dependOn(&run_cmd.step);
}
