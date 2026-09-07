import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

import '../rules/rule_repository.dart';
import '../version.dart';

/// The description is prompt engineering, not documentation: it is what the
/// agent reads when deciding whether this is the moment to record something.
const recordRuleDescription =
    'Record a durable project rule so the next agent or teammate inherits it '
    'instead of working it out again. Use it for a settled decision, a '
    'non-obvious trap, or a standing constraint that must always be followed. '
    'Pass a glob for the files it applies to (for example `lib/models/**`) and '
    'dart_boost files it into a shared, committed markdown note grouped by '
    'area. Keep it to a few lines; only record what you would want to read in '
    'three months. Do not record secrets, transient state, or anything already '
    'obvious from the code.';

class RecordRuleResult {
  const RecordRuleResult({required this.isError, required this.message});

  final bool isError;
  final String message;
}

/// Validates and records. Never throws: an MCP tool that crashes its server is
/// worse than one that returns an error.
Future<RecordRuleResult> recordRule({
  required RuleRepository repository,
  required String glob,
  required String title,
  required String note,
}) async {
  final missing = <String>[
    if (glob.trim().isEmpty) 'glob',
    if (title.trim().isEmpty) 'title',
    if (note.trim().isEmpty) 'note',
  ];

  if (missing.isNotEmpty) {
    return RecordRuleResult(
      isError: true,
      message:
          'Missing required ${missing.length == 1 ? 'parameter' : 'parameters'}: '
          '${missing.join(', ')}.',
    );
  }

  try {
    final result = repository.write(glob: glob, title: title, note: note);
    return RecordRuleResult(
      isError: false,
      message:
          'Recorded in ${result.path}. '
          '${result.created ? 'Created' : 'Appended to'} that file and '
          'regenerated the index.',
    );
  } on ArgumentError {
    return const RecordRuleResult(
      isError: true,
      message:
          'That glob resolves outside the project root. Rules describe '
          'this project, so use a project-relative glob such as `lib/models/**`.',
    );
  } on Object catch (error) {
    return RecordRuleResult(
      isError: true,
      message: 'Could not record the rule: $error',
    );
  }
}

/// The MCP adapter over [RuleRepository]. This is the only file in the
/// package that imports `package:dart_mcp`: it is 0.5.x and explicitly
/// experimental, so confining it here means an upstream break is a one-file
/// fix rather than a scattered one.
base class DartBoostMcpServer extends MCPServer with ToolsSupport {
  DartBoostMcpServer(
    super.channel, {
    required RuleRepository repository,
    required bool rulesEnabled,
  }) : _repository = repository,
       _rulesEnabled = rulesEnabled,
       super.fromStreamChannel(
         implementation: Implementation(
           name: 'dart_boost',
           version: packageVersion,
         ),
         instructions:
             'Exposes record_rule so an agent can save a durable project '
             'rule mid-session instead of re-deriving it next time.',
       ) {
    if (_rulesEnabled) {
      registerTool(_recordRuleTool, _handleRecordRule);
    }
  }

  final RuleRepository _repository;
  final bool _rulesEnabled;

  static final _recordRuleTool = Tool(
    name: 'record_rule',
    description: recordRuleDescription,
    inputSchema: Schema.object(
      properties: {
        'glob': Schema.string(
          description: 'The files this rule applies to, e.g. `lib/models/**`.',
        ),
        'title': Schema.string(description: 'A short title for the rule.'),
        'note': Schema.string(
          description: 'The rule itself, in a few sentences.',
        ),
      },
      required: ['glob', 'title', 'note'],
    ),
  );

  Future<CallToolResult> _handleRecordRule(CallToolRequest request) async {
    final arguments = request.arguments ?? const <String, Object?>{};
    final result = await recordRule(
      repository: _repository,
      glob: arguments['glob'] as String? ?? '',
      title: arguments['title'] as String? ?? '',
      note: arguments['note'] as String? ?? '',
    );

    return CallToolResult(
      isError: result.isError,
      content: [TextContent(text: result.message)],
    );
  }
}

/// `dart run dart_boost:mcp` -- stdio transport, project root is the cwd,
/// which is what every MCP client sets when it launches a server.
Future<void> serveRules({
  required RuleRepository repository,
  required Stream<List<int>> stdin,
  required IOSink stdout,
  bool rulesEnabled = true,
}) async {
  final server = DartBoostMcpServer(
    stdioChannel(input: stdin, output: stdout),
    repository: repository,
    rulesEnabled: rulesEnabled,
  );
  await server.done;
}
