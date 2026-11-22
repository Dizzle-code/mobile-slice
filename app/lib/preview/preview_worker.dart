import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'projector.dart';

/// Long-lived isolate that keeps the mesh and projects it for each camera.
/// While a frame is being computed, only the newest pending request is kept.
class PreviewWorker {
  PreviewWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _frames = StreamController<ProjectedFrame>.broadcast();
  bool _busy = false;
  (OrbitCamera, double, double)? _pending;
  bool _closed = false;

  Stream<ProjectedFrame> get frames => _frames.stream;

  static Future<PreviewWorker> spawn(PreviewScene scene) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_main, replies.sendPort, debugName: 'preview');
    final firstReply = Completer<SendPort>();
    late final PreviewWorker worker;
    replies.listen((message) {
      if (message is SendPort) {
        firstReply.complete(message);
      } else if (message is List) {
        worker._onFrame(message);
      }
    });
    final send = await firstReply.future;
    send.send([
      TransferableTypedData.fromList([scene.triangles]),
      scene.center,
      scene.base,
      scene.radius,
      scene.bedX,
      scene.bedY,
      scene.modelColor,
    ]);
    worker = PreviewWorker._(isolate, send, replies);
    return worker;
  }

  void render(OrbitCamera camera, double width, double height) {
    if (_closed || width <= 0 || height <= 0) return;
    if (_busy) {
      _pending = (camera, width, height);
      return;
    }
    _busy = true;
    _send.send([camera.yaw, camera.pitch, camera.zoom, camera.scale, width, height]);
  }

  /// Projects one frame and waits for it.
  Future<ProjectedFrame> renderOnce(OrbitCamera camera, double width, double height) {
    final next = frames.first;
    render(camera, width, height);
    return next;
  }

  void _onFrame(List message) {
    _busy = false;
    final frame = ProjectedFrame(
      width: message[0] as double,
      height: message[1] as double,
      positions: (message[2] as TransferableTypedData).materialize().asFloat32List(),
      colors: (message[3] as TransferableTypedData).materialize().asInt32List(),
      depths: (message[4] as TransferableTypedData).materialize().asFloat32List(),
      bed: message[5] as Float32List,
      grid: message[6] as Float32List,
    );
    if (!_closed) _frames.add(frame);
    final pending = _pending;
    _pending = null;
    if (pending != null) render(pending.$1, pending.$2, pending.$3);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    _frames.close();
  }

  static void _main(SendPort replies) {
    final inbox = ReceivePort();
    replies.send(inbox.sendPort);
    PreviewScene? scene;
    inbox.listen((message) {
      final m = message as List;
      if (scene == null) {
        scene = PreviewScene(
          triangles: (m[0] as TransferableTypedData).materialize().asFloat32List(),
          center: (m[1] as List).cast<double>(),
          base: (m[2] as List).cast<double>(),
          radius: m[3] as double,
          bedX: m[4] as double,
          bedY: m[5] as double,
          modelColor: m[6] as int,
        );
        return;
      }
      final camera = OrbitCamera(yaw: m[0] as double, pitch: m[1] as double, zoom: m[2] as double, scale: m[3] as double);
      final frame = project(scene!, camera, m[4] as double, m[5] as double);
      replies.send([
        frame.width,
        frame.height,
        TransferableTypedData.fromList([frame.positions]),
        TransferableTypedData.fromList([frame.colors]),
        TransferableTypedData.fromList([frame.depths]),
        frame.bed,
        frame.grid,
      ]);
    });
  }
}
