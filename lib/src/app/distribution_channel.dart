/// The store or feed a build was made for, fixed when it is compiled.
///
/// Stores have different rules, so code that behaves differently between them
/// asks for a capability below, never for a channel by name. This file has no
/// imports: the packaging preflight compiles it on its own.
enum DistributionChannel {
  github(selfUpdates: true, sellsPlus: true),
  msstore(selfUpdates: false, sellsPlus: true),
  fdroid(selfUpdates: false, sellsPlus: true),
  rustore(selfUpdates: false, sellsPlus: false),
  play(selfUpdates: false, sellsPlus: false),
  appstore(selfUpdates: false, sellsPlus: false);

  const DistributionChannel(
      {required this.selfUpdates, required this.sellsPlus});

  /// Only a GitHub build replaces itself; a store updates what it installed.
  final bool selfUpdates;

  /// Whether the store permits the Mosh+ crypto checkout. Purchasing still
  /// needs the billing configuration as well.
  final bool sellsPlus;

  /// The channel named by `MOSH_DISTRIBUTION_CHANNEL`.
  factory DistributionChannel.fromEnvironment() =>
      parse(const String.fromEnvironment('MOSH_DISTRIBUTION_CHANNEL'));

  /// Unset or empty is the GitHub release, so existing builds and forks keep
  /// today's behaviour. An unknown name fails rather than guessing store rules.
  static DistributionChannel parse(String name) {
    if (name.isEmpty) return github;
    final channel = values.asNameMap()[name];
    if (channel == null) {
      throw const FormatException('Invalid distribution channel configuration');
    }
    return channel;
  }
}
