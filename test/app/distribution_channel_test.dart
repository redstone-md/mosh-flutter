import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/distribution_channel.dart';

void main() {
  test('a build without a channel is the GitHub release; names select a store',
      () {
    expect(DistributionChannel.parse(''), DistributionChannel.github);
    expect(DistributionChannel.parse('rustore'), DistributionChannel.rustore);
  });

  test('only GitHub updates itself; stores that allow it sell Mosh+', () {
    final updating = {
      for (final channel in DistributionChannel.values)
        if (channel.selfUpdates) channel.name
    };
    final selling = {
      for (final channel in DistributionChannel.values)
        if (channel.sellsPlus) channel.name
    };
    expect(updating, {'github'});
    expect(selling, {'github', 'msstore', 'fdroid'});
  });

  test('an unknown channel fails instead of picking store rules', () {
    for (final name in ['GitHub', 'rustore ', 'web']) {
      expect(() => DistributionChannel.parse(name), throwsFormatException);
    }
  });
}
