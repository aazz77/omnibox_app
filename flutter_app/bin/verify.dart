// verify.dart —— 命令行最小验证：Dart ffi 调 Rust cdylib
// 运行: dart run bin/verify.dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

void main(List<String> args) {
  final name = Platform.isWindows ? 'omnibox_core.dll' : 'libomnibox_core.so';
  final libPath = args.isNotEmpty
      ? args[0]
      : '/workspace/omnibox-desktop/rust_core/target/release/$name';
  print('加载库: $libPath');
  final lib = DynamicLibrary.open(libPath);

  // ob_init
  final init = lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Utf8>, Pointer<Utf8>)>('ob_init');
  final d = '/tmp/omnibox-ffi-verify'.toNativeUtf8();
  final t = ''.toNativeUtf8();
  print('ob_init => ${init(d, t)}');
  malloc.free(d);
  malloc.free(t);

  // ob_hello
  final hello = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('ob_hello');
  print('ob_hello => ${_take(lib, hello())}');

  // health
  print('health => ${_call(lib, 'health', {})}');

  // 导入如意脚本
  final ruyiPath = args.length > 1 ? args[1] : '/tmp/ruyi.js';
  final src = File(ruyiPath).readAsStringSync();
  print('导入如意脚本 (${src.length} 字符) => ${_call(lib, 'spiders_add', {'name': 'ruyi.js', 'source': src, 'runtime': 'quickjs'})}');

  // 搜索
  final sw = Stopwatch()..start();
  final res = _call(lib, 'search', {'src': 'all', 'wd': '西游记', 'page': 1});
  sw.stop();
  final list = res['list'] as List? ?? [];
  print('search => ok=${res['ok']} 条数=${list.length} 耗时=${sw.elapsedMilliseconds}ms');
  if (list.isNotEmpty) {
    print('首条: ${list.first['vod_name']} (${list.first['vod_id']})');
  } else {
    print('错误: ${res['error']}');
  }
}

Map<String, dynamic> _call(DynamicLibrary lib, String method, Map<String, dynamic> params) {
  final fn = lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('ob_call');
  final m = method.toNativeUtf8();
  final p = jsonEncode(params).toNativeUtf8();
  try {
    return _take(lib, fn(m, p));
  } finally {
    malloc.free(m);
    malloc.free(p);
  }
}

Map<String, dynamic> _take(DynamicLibrary lib, Pointer<Utf8> ptr) {
  final s = ptr.toDartString();
  lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('ob_free')(ptr);
  return jsonDecode(s) as Map<String, dynamic>;
}
