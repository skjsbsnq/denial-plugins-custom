import 'taskbar_preferences.dart';

/// Reuse catalog identities across window/focus updates. The public shell
/// service supplies immutable list snapshots; replacing a snapshot rebuilds
/// only the corresponding index.
class ApplicationIdentityIndex<T> {
  ApplicationIdentityIndex({
    required this.idOf,
    required this.appIdOf,
    required this.aliasesOf,
  });

  final String Function(T) idOf;
  final String Function(T) appIdOf;
  final Iterable<String> Function(T) aliasesOf;
  List<T>? _catalog;
  List<PinnedApplication>? _pins;
  final _exact = <String, T>{};
  final _aliases = <String, T?>{};
  final _groups = <String, T>{};
  final _pinnedIdentities = <String, String>{};

  void update(List<T> catalog, List<PinnedApplication> pins) {
    if (!identical(catalog, _catalog)) {
      _catalog = catalog;
      _exact.clear();
      _aliases.clear();
      _groups.clear();
      for (final app in catalog) {
        _exact.putIfAbsent(normalizeApplicationId(appIdOf(app)), () => app);
        _groups.putIfAbsent(
          'app:${normalizeApplicationId(idOf(app))}',
          () => app,
        );
        // The previous lookup used `any`: repeated aliases within one entry
        // count once, while matching separate catalog entries are ambiguous.
        final aliases = aliasesOf(app).map(normalizeApplicationId).toSet();
        for (final alias in aliases) {
          if (_aliases.containsKey(alias)) {
            _aliases[alias] = null;
          } else {
            _aliases[alias] = app;
          }
        }
      }
    }
    if (!identical(pins, _pins)) {
      _pins = pins;
      _pinnedIdentities.clear();
      for (final pin in pins) {
        _pinnedIdentities.putIfAbsent(
          normalizeApplicationId(pin.appId),
          () => pin.id,
        );
      }
    }
  }

  T? applicationFor(String appId) {
    final normalized = normalizeApplicationId(appId);
    // Exact desktop IDs always win over aliases, including ambiguous aliases.
    return _exact[normalized] ?? _aliases[normalized];
  }

  T? applicationForGroup(String key) => _groups[key];

  String groupIdentity(String appId) {
    final app = applicationFor(appId);
    if (app != null) return idOf(app);
    return _pinnedIdentities[normalizeApplicationId(appId)] ?? appId;
  }
}
