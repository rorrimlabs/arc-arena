import 'package:arena_ops/data/sync/sync_transport.dart';

/// Plays the server. [onPush] decides each op's fate; pulls return [pages].
class ScriptedTransport implements SyncTransport {
  OpResult Function(OutgoingOp op)? onPush;
  Object? pushThrows;
  final pushed = <OutgoingOp>[];
  int pulls = 0;
  List<PullPage> pages = [];
  List<EntityRows> entities = [];

  @override
  Future<List<OpResult>> push(String arenaId, List<OutgoingOp> ops, String deviceId) async {
    final t = pushThrows;
    if (t != null) throw t;
    final out = <OpResult>[];
    for (final o in ops) {
      pushed.add(o);
      final r = onPush?.call(o) ?? OpResult(opId: o.opId, status: 'applied');
      out.add(r);
      if (r.status == 'retry') break; // as sync_push: stop to keep order
    }
    return out;
  }

  @override
  Future<PullPage> pull(String arenaId, String cursor, {int limit = 2000}) async {
    pulls++;
    if (pages.isEmpty) {
      return PullPage(cursor: cursor, hasMore: false, changes: const []);
    }
    return pages.removeAt(0);
  }

  @override
  Future<List<EntityRows>> fetchEntities(
          String arenaId, List<({String type, String id})> refs) async =>
      [
        for (final r in refs)
          entities.firstWhere((e) => e.type == r.type && e.id == r.id,
              orElse: () => (type: r.type, id: r.id, rows: const [])),
      ];
}
