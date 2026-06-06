import 'package:cyxchat/providers/network_provider.dart';
import 'package:cyxchat/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap resolution falls back to default server', () {
    expect(
      resolveBootstrapServer(settings: const AppSettings()),
      SettingsDefaults.bootstrapServer,
    );
  });

  test('bootstrap resolution prefers saved setting and explicit override', () {
    const settings = AppSettings(bootstrapServer: '10.0.0.1:7777');

    expect(
      resolveBootstrapServer(settings: settings),
      '10.0.0.1:7777',
    );
    expect(
      resolveBootstrapServer(
        override: '127.0.0.1:7777',
        settings: settings,
      ),
      '127.0.0.1:7777',
    );
  });
}
