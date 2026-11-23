// 占位 smoke test：验证测试框架可用。
// 真实 App 依赖 Rust FFI 动态库，无法在无内核的测试环境实例化，
// 故这里只做一个最小的 Widget 测试，避免 analyze / test 因不存在的 MyApp 报错。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('OmniBox'))));
    expect(find.text('OmniBox'), findsOneWidget);
  });
}
