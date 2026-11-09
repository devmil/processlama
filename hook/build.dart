import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    output.dependencies.addAll(await _rustBuildDependencies(input.packageRoot));

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final rustTarget = _rustTargetTriple(targetOS, targetArch);
    final cargoEnvironment = await _cargoEnvironment(
      input.config.code,
      rustTarget,
    );

    final manifestPath = input.packageRoot.resolve('rust-core/Cargo.toml');
    // Flutter enables native linking for AOT builds (profile and release).
    // The Rust compiler profile and artifact path must describe the same build.
    final useRelease = input.config.linkingEnabled;
    final profile = useRelease ? 'release' : 'debug';

    final cargoArgs = <String>[
      'build',
      '--manifest-path',
      manifestPath.toFilePath(),
      // The workspace also holds the remote helper; only the bridge library
      // belongs in the application bundle.
      '--package',
      'processlama_core',
      '--locked',
      if (useRelease) '--release',
      if (rustTarget != null) ...['--target', rustTarget],
    ];

    final result = await Process.run(
      'cargo',
      cargoArgs,
      workingDirectory: input.packageRoot.toFilePath(),
      environment: cargoEnvironment,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'cargo build failed (${result.exitCode}):\n${result.stderr}',
      );
    }

    final libraryName = targetOS.dylibFileName('processlama_core');
    final targetOverride = Platform.environment['CARGO_TARGET_DIR'];
    final targetRoot = targetOverride == null || targetOverride.isEmpty
        ? input.packageRoot.resolve('rust-core/target/')
        : Directory(targetOverride).isAbsolute
        ? Directory(targetOverride).uri
        : input.packageRoot.resolveUri(Uri.directory(targetOverride));
    final libraryUri = rustTarget != null
        ? targetRoot.resolve('$rustTarget/$profile/$libraryName')
        : targetRoot.resolve('$profile/$libraryName');
    final bundledLibrary = input.outputDirectory.resolve(libraryName);
    await File.fromUri(libraryUri).copy(bundledLibrary.toFilePath());

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'processlama_core.dart',
        linkMode: DynamicLoadingBundled(),
        file: bundledLibrary,
      ),
    );

    // Development builds also build the remote helper for this computer into
    // build/remote-helper-dev/ (never bundled by the package scripts), so
    // a debug app can install it on a host of the same platform. Release
    // packages bundle all four helpers from CI instead. Opt out with
    // `hooks: user_defines: processlama: dev_remote_helper: false`.
    final helperTarget = _remoteHelperTarget(targetOS, targetArch);
    if (!useRelease &&
        helperTarget != null &&
        input.userDefines['dev_remote_helper'] != false) {
      await _buildDevRemoteHelper(
        input.packageRoot,
        manifestPath,
        rustTarget,
        helperTarget,
        targetRoot,
        cargoEnvironment,
      );
    }
  });
}

/// The helper target of a development host, or null where no helper exists.
String? _remoteHelperTarget(OS os, Architecture arch) => switch ((os, arch)) {
  (OS.linux, Architecture.x64) => 'linux-x86_64',
  (OS.linux, Architecture.arm64) => 'linux-arm64',
  (OS.macOS, Architecture.arm64) => 'macos-arm64',
  (OS.macOS, Architecture.x64) => 'macos-x86_64',
  _ => null,
};

Future<void> _buildDevRemoteHelper(
  Uri packageRoot,
  Uri manifestPath,
  String? rustTarget,
  String helperTarget,
  Uri targetRoot,
  Map<String, String> cargoEnvironment,
) async {
  const profile = 'helper-dev';
  final build = await Process.run(
    'cargo',
    [
      'build',
      '--manifest-path',
      manifestPath.toFilePath(),
      '--package',
      'processlama-remote-helper',
      '--locked',
      '--profile',
      profile,
      if (rustTarget != null) ...['--target', rustTarget],
    ],
    workingDirectory: packageRoot.toFilePath(),
    environment: cargoEnvironment,
  );
  if (build.exitCode != 0) {
    throw StateError(
      'cargo build of the remote helper failed (${build.exitCode}):\n'
      '${build.stderr}',
    );
  }
  final binary = rustTarget != null
      ? targetRoot.resolve('$rustTarget/$profile/processlama-remote-helper')
      : targetRoot.resolve('$profile/processlama-remote-helper');
  final describe = await Process.run('python3', [
    packageRoot.resolve('scripts/package_remote_helper.py').toFilePath(),
    'package',
    '--target',
    helperTarget,
    '--binary',
    binary.toFilePath(),
    '--output',
    packageRoot.resolve('build/remote-helper-dev/').toFilePath(),
    '--no-archive',
    '--development',
  ], workingDirectory: packageRoot.toFilePath());
  if (describe.exitCode != 0) {
    throw StateError(
      'packaging the development remote helper failed:\n${describe.stderr}',
    );
  }
}

/// Every workspace manifest and Rust source, so a change in any crate the
/// bridge library links rebuilds it. Cargo target directories are skipped.
Future<List<Uri>> _rustBuildDependencies(Uri packageRoot) async {
  final dependencies = <Uri>[
    packageRoot.resolve('hook/build.dart'),
    packageRoot.resolve('rust-core/Cargo.toml'),
    packageRoot.resolve('rust-core/Cargo.lock'),
  ];

  final workspace = Directory.fromUri(packageRoot.resolve('rust-core/'));
  if (!workspace.existsSync()) return dependencies;
  final pending = <Directory>[workspace];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      if (entity is Directory) {
        if (name == 'target' || name.startsWith('.')) continue;
        dependencies.add(entity.uri);
        pending.add(entity);
      } else if (entity is File &&
          entity.parent.path != workspace.path &&
          (name.endsWith('.rs') ||
              name == 'Cargo.toml' ||
              name == 'COMPATIBILITY')) {
        dependencies.add(entity.uri);
      }
    }
  }

  return dependencies;
}

Future<Map<String, String>> _cargoEnvironment(
  CodeConfig codeConfig,
  String? rustTarget,
) async {
  final environment = <String, String>{};
  final cCompiler = codeConfig.cCompiler;
  // On Windows, cc must discover MSVC itself so it gets the compiler's SDK
  // environment. An absolute CC path bypasses that discovery.
  if (cCompiler != null && codeConfig.targetOS != OS.windows) {
    final cc = cCompiler.compiler.toFilePath();
    final ar = cCompiler.archiver.toFilePath();
    environment['CC'] = cc;
    environment['AR'] = ar;
    environment['LD'] = cCompiler.linker.toFilePath();
    if (rustTarget != null) {
      final targetKey = rustTarget.replaceAll('-', '_');
      environment['CC_$targetKey'] = cc;
      environment['AR_$targetKey'] = ar;
    }
  }

  if (codeConfig.targetOS == OS.macOS) {
    final sdkRoot = await _xcrun(['--sdk', 'macosx', '--show-sdk-path']);
    final deploymentTarget = '${codeConfig.macOS.targetVersion}.0';
    environment['SDKROOT'] = sdkRoot;
    environment['MACOSX_DEPLOYMENT_TARGET'] = deploymentTarget;
    final cflags = '-isysroot $sdkRoot -mmacosx-version-min=$deploymentTarget';
    environment['CFLAGS'] = cflags;
    environment['CXXFLAGS'] = cflags;
    if (rustTarget != null) {
      final targetKey = rustTarget.replaceAll('-', '_');
      environment['CFLAGS_$targetKey'] = cflags;
      environment['CXXFLAGS_$targetKey'] = cflags;
    }
  }

  return environment;
}

Future<String> _xcrun(List<String> args) async {
  final result = await Process.run('xcrun', args);
  if (result.exitCode != 0) {
    throw StateError(
      'xcrun ${args.join(' ')} failed (${result.exitCode}):\n'
      '${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

String? _rustTargetTriple(OS os, Architecture arch) {
  return switch (os) {
    OS.macOS => switch (arch) {
      Architecture.arm64 => 'aarch64-apple-darwin',
      Architecture.x64 => 'x86_64-apple-darwin',
      _ => null,
    },
    OS.linux => switch (arch) {
      Architecture.arm64 => 'aarch64-unknown-linux-gnu',
      Architecture.x64 => 'x86_64-unknown-linux-gnu',
      _ => null,
    },
    OS.windows => switch (arch) {
      Architecture.x64 => 'x86_64-pc-windows-msvc',
      Architecture.arm64 => 'aarch64-pc-windows-msvc',
      _ => null,
    },
    _ => null,
  };
}
