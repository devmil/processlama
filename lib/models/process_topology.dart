import 'process_identity.dart';

/// Immutable parent/child index shared by metric-only samples. Native cache
/// versions are runtime tokens and are deliberately excluded from saved files.
class ProcessTopology {
  ProcessTopology({
    this.version,
    required Map<ProcessIdentity, ProcessIdentity?> parents,
  }) : parentByIdentity = Map.unmodifiable(parents),
       childrenByParent = _children(parents);

  final int? version;
  final Map<ProcessIdentity, ProcessIdentity?> parentByIdentity;
  final Map<ProcessIdentity?, List<ProcessIdentity>> childrenByParent;

  static Map<ProcessIdentity?, List<ProcessIdentity>> _children(
    Map<ProcessIdentity, ProcessIdentity?> parents,
  ) {
    final children = <ProcessIdentity?, List<ProcessIdentity>>{};
    for (final entry in parents.entries) {
      children.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    return Map.unmodifiable({
      for (final entry in children.entries)
        entry.key: List<ProcessIdentity>.unmodifiable(entry.value),
    });
  }
}
