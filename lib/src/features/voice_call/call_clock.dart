String formatCallClock(BigInt elapsedMs) {
  final total =
      elapsedMs <= BigInt.zero ? 0 : (elapsedMs ~/ BigInt.from(1000)).toInt();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
