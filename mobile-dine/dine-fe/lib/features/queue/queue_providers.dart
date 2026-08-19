import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../models/ops.dart';

/// Cooldown panggilan suara di server (cache `last_audio_call`) — 15 detik.
const int kQueueCallCooldown = 15;

/// Papan antrian hari ini + ringkasan status + sisa cooldown panggilan.
class QueueBoard {
  const QueueBoard({
    required this.queues,
    required this.cooldownLeft,
    required this.waiting,
    required this.called,
    required this.seated,
  });

  final List<QueueModel> queues;

  /// Sisa detik sebelum boleh memanggil lagi (0 = bebas memanggil).
  final int cooldownLeft;
  final int waiting;
  final int called;
  final int seated;

  factory QueueBoard.fromResponse(ApiResponse res) {
    final raw = res.asMap['summary'];
    final summary = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};

    return QueueBoard(
      queues: res.listAt('queues').map(QueueModel.fromJson).toList(),
      cooldownLeft: J.toInt(res.asMap['cooldown_left']),
      waiting: J.toInt(summary['waiting']),
      called: J.toInt(summary['called']),
      seated: J.toInt(summary['seated']),
    );
  }
}

/// Hasil panggilan antrian: pesan server + cooldown baru.
class QueueCallResult {
  const QueueCallResult({required this.message, required this.cooldownLeft});

  final String message;
  final int cooldownLeft;
}

/// GET /queues
final queueBoardProvider = FutureProvider<QueueBoard>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/queues');
  return QueueBoard.fromResponse(res);
});

/// Aksi tulis layar antrian.
class QueueRepo {
  const QueueRepo(this._api);

  final ApiClient _api;

  /// POST /queues/{id}/call — 429 bila masih dalam cooldown.
  Future<QueueCallResult> call(int id) async {
    final res = await _api.post('/queues/$id/call');
    final left = J.toInt(res.asMap['cooldown_left']);

    return QueueCallResult(
      message: res.message,
      cooldownLeft: left == 0 ? kQueueCallCooldown : left,
    );
  }

  /// POST /queues/{id}/status — waiting | called | seated | cancelled.
  Future<String> setStatus(int id, String status) async {
    final res = await _api.post('/queues/$id/status', data: {'status': status});
    return res.message;
  }
}

final queueRepoProvider = Provider<QueueRepo>(
  (ref) => QueueRepo(ref.watch(apiClientProvider)),
);
