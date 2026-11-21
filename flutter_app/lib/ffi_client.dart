import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// OmniBox Rust 内核 API 客户端（异步）。
/// 阻塞式 FFI 调用通过 Isolate.spawn 丢到后台 isolate，UI 主线程不阻塞。
/// DynamicLibrary 句柄不可跨 isolate 传递，故每个 isolate 内独立打开。
/// 不依赖 flutter/foundation，纯 dart 也可验证（等价于 Flutter compute()）。
class OmniBoxApi {
  final String libraryPath;

  OmniBoxApi(this.libraryPath);

  static String defaultPath() {
    final name = Platform.isWindows ? 'omnibox_core.dll' : 'libomnibox_core.so';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final local = '$exeDir${Platform.pathSeparator}$name';
    if (File(local).existsSync()) return local;
    return '/workspace/omnibox-desktop/rust_core/target/release/$name';
  }

  /// 同步初始化（仅启动时调用一次，很快）：设置数据目录/口令。
  bool initSync(String dataDir, {String? adminToken}) {
    final lib = DynamicLibrary.open(libraryPath);
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('ob_init');
    final d = dataDir.toNativeUtf8();
    final t = (adminToken ?? '').toNativeUtf8();
    try {
      return fn(d, t) == 1;
    } finally {
      malloc.free(d);
      malloc.free(t);
    }
  }

  /// 通用 RPC（后台 isolate 执行）
  Future<Map<String, dynamic>> call(String method, [Map<String, dynamic> params = const {}]) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn<_Req>(
      _callIsolate,
      _Req(port.sendPort, libraryPath, method, params),
    );
    try {
      return await port.first as Map<String, dynamic>;
    } finally {
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }

  /// 取图片字节（后台 isolate 执行），返回 null 表示失败
  Future<ImageBytes?> image(String url) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn<_ImgReq>(
      _imageIsolate,
      _ImgReq(port.sendPort, libraryPath, url),
    );
    try {
      final r = await port.first;
      if (r == null) return null;
      final m = r as Map<String, dynamic>;
      return ImageBytes(m['bytes'] as Uint8List, m['mime'] as String);
    } finally {
      port.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }
}

class ImageBytes {
  final Uint8List bytes;
  final String mime;
  ImageBytes(this.bytes, this.mime);
}

// ===== isolate 消息与入口 =====

class _Req {
  final SendPort reply;
  final String lib;
  final String method;
  final Map<String, dynamic> params;
  _Req(this.reply, this.lib, this.method, this.params);
}

class _ImgReq {
  final SendPort reply;
  final String lib;
  final String url;
  _ImgReq(this.reply, this.lib, this.url);
}

void _callIsolate(_Req req) {
  final lib = DynamicLibrary.open(req.lib);
  final fn = lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('ob_call');
  final m = req.method.toNativeUtf8();
  final p = jsonEncode(req.params).toNativeUtf8();
  late final Map<String, dynamic> result;
  try {
    result = _take(lib, fn(m, p));
  } finally {
    malloc.free(m);
    malloc.free(p);
  }
  req.reply.send(result);
}

void _imageIsolate(_ImgReq req) {
  final lib = DynamicLibrary.open(req.lib);
  final imgFn = lib.lookupFunction<
      Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Uint64>, Pointer<Pointer<Utf8>>),
      Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Uint64>, Pointer<Pointer<Utf8>>)>('ob_img');
  final freeBytes = lib.lookupFunction<Void Function(Pointer<Uint8>, Uint64),
      void Function(Pointer<Uint8>, int)>('ob_free_bytes');
  final freeStr = lib.lookupFunction<Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('ob_free');
  final u = req.url.toNativeUtf8();
  final outLen = malloc<Uint64>();
  final outCtype = malloc<Pointer<Utf8>>();
  Map<String, dynamic>? result;
  try {
    final ptr = imgFn(u, outLen.cast(), outCtype);
    final len = outLen.value.toInt();
    final ctypePtr = outCtype.value;
    if (ptr == nullptr) {
      if (ctypePtr != nullptr) freeStr(ctypePtr);
    } else {
      final bytes = Uint8List.fromList(ptr.asTypedList(len));
      final mime = ctypePtr == nullptr ? 'image/jpeg' : ctypePtr.toDartString();
      freeBytes(ptr, len);
      if (ctypePtr != nullptr) freeStr(ctypePtr);
      result = <String, dynamic>{'bytes': bytes, 'mime': mime};
    }
  } finally {
    malloc.free(u);
    malloc.free(outLen);
    malloc.free(outCtype);
  }
  req.reply.send(result);
}

Map<String, dynamic> _take(DynamicLibrary lib, Pointer<Utf8> ptr) {
  final s = ptr.toDartString();
  lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('ob_free')(ptr);
  try {
    final v = jsonDecode(s);
    if (v is Map<String, dynamic>) return v;
    return {'ok': false, 'error': '返回不是对象', 'raw': s};
  } catch (e) {
    return {'ok': false, 'error': 'JSON 解析失败: $e', 'raw': s};
  }
}
