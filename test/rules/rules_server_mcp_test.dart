@TestOn('vm')
library;

// Exercises DartBoostMcpServer over an in-memory MCP client/server pair, the
// way the spec promised: package:dart_mcp connects a client and server over
// a StreamChannel, so record_rule is driven through the real protocol
// (tools/list, tools/call, schema validation) without spawning a subprocess.
//
// The wiring mirrors package:dart_mcp's own
// test/client_and_server_test.dart and test/test_utils.dart: a
// StreamChannelController hands out two ends of one pipe (`local` and
// `foreign` are already cross-wired), an `MCPClient` connects over one end,
// and the server under test is constructed on the other.

import 'dart:async';

import 'package:dart_boost/src/mcp/rules_server.dart';
import 'package:dart_boost/src/rules/rule_repository.dart';
import 'package:dart_mcp/client.dart';
import 'package:file/memory.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  late RuleRepository repo;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/app').createSync(recursive: true);
    repo = RuleRepository(fileSystem: fs, projectRoot: fs.directory('/app'));
  });

  /// Wires an [MCPClient] to a fresh [DartBoostMcpServer] over an in-memory
  /// [StreamChannelController] and completes the initialize handshake, the
  /// same sequence a real MCP host performs before issuing any tool calls.
  Future<ServerConnection> connect({
    required RuleRepository repository,
    required bool rulesEnabled,
  }) async {
    final controller = StreamChannelController<String>();
    final client = MCPClient(
      Implementation(name: 'test client', version: '0.1.0'),
    );
    final connection = client.connectServer(controller.local);
    DartBoostMcpServer(
      controller.foreign,
      repository: repository,
      rulesEnabled: rulesEnabled,
    );

    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized(InitializedNotification());
    addTearDown(connection.shutdown);
    return connection;
  }

  test('tools/list returns record_rule when rules are enabled', () async {
    final connection = await connect(repository: repo, rulesEnabled: true);

    final result = await connection.listTools();

    expect(result.tools, hasLength(1));
    expect(result.tools.single.name, 'record_rule');
  });

  test('tools/list returns nothing when rules are disabled', () async {
    final connection = await connect(repository: repo, rulesEnabled: false);

    final result = await connection.listTools();

    expect(result.tools, isEmpty);
  });

  test(
    'tools/call with valid arguments records the rule and regenerates the index',
    () async {
      final connection = await connect(repository: repo, rulesEnabled: true);

      final result = await connection.callTool(
        CallToolRequest(
          name: 'record_rule',
          arguments: {
            'glob': 'lib/models/**',
            'title': 'Money is integer cents',
            'note': 'Use `int` cents.',
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(fs.file('/app/.ai/rules/models.md').existsSync(), isTrue);
      expect(fs.file('/app/.ai/rules/index.md').existsSync(), isTrue);
    },
  );

  test('tools/call with a missing required argument returns an error and the '
      'server keeps serving requests', () async {
    final connection = await connect(repository: repo, rulesEnabled: true);

    final result = await connection.callTool(
      CallToolRequest(
        name: 'record_rule',
        arguments: {'glob': 'lib/models/**', 'title': 'Money'},
      ),
    );

    expect(result.isError, isTrue);
    expect(fs.directory('/app/.ai/rules').existsSync(), isFalse);

    // The server must still be usable after a rejected call.
    final followUp = await connection.listTools();
    expect(followUp.tools.single.name, 'record_rule');
  });

  test('tools/call with a wrong-typed argument returns an error and the server '
      'keeps serving requests', () async {
    final connection = await connect(repository: repo, rulesEnabled: true);

    final result = await connection.callTool(
      CallToolRequest(
        name: 'record_rule',
        arguments: {
          'glob': 'lib/models/**',
          'title': 123,
          'note': 'Use `int` cents.',
        },
      ),
    );

    expect(result.isError, isTrue);
    expect(fs.directory('/app/.ai/rules').existsSync(), isFalse);

    // The server must still be usable after a rejected call.
    final followUp = await connection.listTools();
    expect(followUp.tools.single.name, 'record_rule');
  });
}
