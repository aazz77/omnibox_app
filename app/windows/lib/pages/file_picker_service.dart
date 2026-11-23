// 本地占位实现（无 file_picker 依赖，保证本地 analyze 通过）。
// CI 构建时 workflow 会用 file_picker_service.dart.txt 覆盖本文件，
// 从而启用真正的系统文件选择对话框。
import 'dart:io';

Future<Map<String, String>?> pickJsFile() async {
  // 真正的实现见 file_picker_service.dart.txt（CI 中启用）。
  // 本地 Flutter 环境无 file_picker 插件，仅保留签名占位。
  return null;
}

/// 选择本地 M3U/M3U8/TXT 播放列表，返回 {name, path}；用户取消返回 null。
Future<Map<String, String>?> pickM3uFile() async {
  // 真正的实现见 file_picker_service.dart.txt（CI 中启用）。
  return null;
}

/// 选择本地 JSON 关注列表，返回 {name, source}；用户取消返回 null。
Future<Map<String, String>?> pickJsonFile() async {
  // 真正的实现见 file_picker_service.dart.txt（CI 中启用）。
  return null;
}
