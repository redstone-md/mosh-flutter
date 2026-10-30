// Related contract cases share one test process; fixtures stay library-private.
import 'package:flutter_test/flutter_test.dart';

import 'peer_label_cases.dart' as peer_label;
import 'message_selection_model_cases.dart' as message_selection_model;
import 'conversation_snapshot_cases.dart' as conversation_snapshot;
import 'conversation_dm_offer_cases.dart' as conversation_dm_offer;

void main() {
  group('peer_label', peer_label.main);
  group('message_selection_model', message_selection_model.main);
  group('conversation_snapshot', conversation_snapshot.main);
  group('conversation_dm_offer', conversation_dm_offer.main);
}
