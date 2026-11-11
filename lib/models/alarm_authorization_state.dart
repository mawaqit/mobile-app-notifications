/// The iOS Alarms (AlarmKit) permission, which "Play full Adhan" needs.
///
/// Mirrors `AlarmManager.AuthorizationState` on iOS 26+. [unsupported] covers
/// everything else: Android, iOS below 26, or a native call that failed.
enum AlarmAuthorizationState {
  notDetermined,
  authorized,
  denied,
  unsupported;

  /// Parses the name the native side sends; anything unknown is [unsupported].
  static AlarmAuthorizationState fromName(Object? name) {
    for (final state in values) {
      if (state.name == name) return state;
    }
    return unsupported;
  }

  bool get isAuthorized => this == authorized;
}
