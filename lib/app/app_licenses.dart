import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The license documents ProcessLama bundles as assets, and the packages
/// each one covers in the license dialog.
const processLamaLicenseAssets = <({String path, List<String> packages})>[
  (path: 'LICENSE', packages: ['ProcessLama']),
  (path: 'LICENSES/NOTICE.txt', packages: ['ProcessLama notices']),
  (
    path: 'LICENSES/GPL-2.0-only.txt',
    packages: ['ProcessLama network eBPF program'],
  ),
  (path: 'LICENSES/libbpf-BSD-2-Clause.txt', packages: ['libbpf']),
  (path: 'LICENSES/libbpf-rs-BSD-2-Clause.txt', packages: ['libbpf-rs']),
  (path: 'LICENSES/Geist-OFL-1.1.txt', packages: ['Geist']),
  (
    path: 'LICENSES/upstream-dart-sys-LICENSE-MIT.md.txt',
    packages: ['dart-sys'],
  ),
  (
    path: 'LICENSES/upstream-dart-sys-LICENSE-APACHE-2.0.md.txt',
    packages: ['dart-sys'],
  ),
  (
    path: 'LICENSES/upstream-flutter_rust_bridge-LICENSE.txt',
    packages: ['flutter_rust_bridge'],
  ),
  (
    path: 'LICENSES/FLUTTER-DEPENDENCIES.md',
    packages: ['Flutter production dependencies'],
  ),
  (
    path: 'LICENSES/RUST-DEPENDENCIES.md',
    packages: ['Rust production dependencies'],
  ),
];

var _registered = false;

/// Adds ProcessLama's own license and the bundled notices to
/// [LicenseRegistry], next to the Flutter engine's notices. Safe to call
/// more than once.
void registerProcessLamaLicenses({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  final source = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final document in processLamaLicenseAssets) {
      final text = await source.loadString(document.path);
      yield LicenseEntryWithLineBreaks(document.packages, text);
    }
  });
}
