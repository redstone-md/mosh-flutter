import 'package:mosh/src/rust/api/background/types.dart';
import 'package:mosh/src/rust/persistence/user_transfers/types.dart';

BackgroundStatus backgroundStatus({List<UserTransfer> transfers = const []}) =>
    BackgroundStatus(
        revision: BigInt.one,
        interactive: false,
        waitingEnabled: false,
        requestedMode: BackgroundMode.offline,
        actualMode: BackgroundMode.offline,
        reachability: BackgroundReachability.unavailable,
        attachmentCount: 0,
        currentCalls: 0,
        currentUserTransfers: 0,
        userTransfers: transfers);
