/// A path-scoped block, carved out of a fragment for an agent that supports
/// per-directory rules.
///
/// Nothing produces these yet -- the channel exists so path-scoped rules can
/// be added without changing the renderer's return type or every caller.
class ScopedBlock {
  const ScopedBlock({required this.paths, required this.body});

  final List<String> paths;
  final String body;
}

class RenderResult {
  const RenderResult({
    required this.content,
    this.unknownFlags = const <String>{},
    this.unknownVars = const <String>{},
    this.scopedBlocks = const <ScopedBlock>[],
    this.errors = const <String>[],
  });

  final String content;

  /// Flags referenced by the fragment that the facts object does not define.
  /// Each was treated as `false`.
  final Set<String> unknownFlags;

  /// Variables referenced by the fragment that the facts object does not
  /// define. Each was left in the output verbatim.
  final Set<String> unknownVars;

  /// Reserved. See [ScopedBlock].
  final List<ScopedBlock> scopedBlocks;

  /// Structural problems (unbalanced directives). Never fatal.
  final List<String> errors;

  bool get isClean =>
      unknownFlags.isEmpty && unknownVars.isEmpty && errors.isEmpty;
}

/// The whole template language, deliberately.
///
/// Boost renders Blade and needs an entire escaping layer to survive
/// Markdown-with-code (`RendersBladeGuidelines` string-swaps backticks,
/// `<?php`, `@can`, `@include` and `<x-` for sentinels before rendering). Any
/// general engine in Dart would need the same layer, so there isn't one here.
///
/// Two properties make this strictly better than adopting one:
///
/// 1. Fenced code blocks are masked first, always. Nothing inside a fence is
///    ever touched, so embedding literal code samples is a non-issue rather
///    than a running battle.
/// 2. The directives are HTML comments, so they vanish in a rendered Markdown
///    preview -- a fragment reads correctly *unprocessed*, on GitHub.
///
/// ```markdown
/// <!--boost:if usesRiverpod3-->
/// Riverpod 3 removed `StateProvider`. Use `NotifierProvider`.
/// <!--boost:else-->
/// `StateNotifierProvider` still exists but prefer `NotifierProvider`.
/// <!--boost:end-->
///
/// Run `{{ dartRunCommand }} build_runner build -d` after editing providers.
/// ```
///
/// A bad fragment -- especially a third-party one -- must degrade, never
/// abort the install: an unknown flag is `false` plus a warning, an unknown
/// variable is left literal plus a warning, and nothing throws.
class GuidelineRenderer {
  const GuidelineRenderer();

  static final _directive = RegExp(
    r'^<!--\s*boost:(if|else|end)(?:\s+([A-Za-z_][A-Za-z0-9_]*))?\s*-->$',
  );

  static final _variable = RegExp(r'\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}');

  static final _fence = RegExp(r'^(\s{0,3})(`{3,}|~{3,})(.*)$');

  /// A flag name that *looks* like one of ours but is not currently true is
  /// simply false; anything not shaped like a flag is a typo worth reporting.
  static final _flagShaped = RegExp(r'^(uses|is|has|no)[A-Z0-9]');

  RenderResult render(
    String source, {
    required Set<String> flags,
    required Map<String, String> variables,
    bool Function(String name)? isKnownFlag,
  }) {
    final unknownFlags = <String>{};
    final unknownVars = <String>{};
    final errors = <String>[];
    // Collected and joined rather than written, so a source with (or without)
    // a trailing newline round-trips exactly.
    final out = <String>[];

    final knownFlag = isKnownFlag ?? _flagShaped.hasMatch;

    final lines = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    // A single forward pass with an emit stack, so nesting is free.
    final stack = <_Frame>[];
    var emitting = true;

    String? fenceMarker;
    var fenceLength = 0;

    for (final line in lines) {
      if (fenceMarker != null) {
        // Inside a fence: verbatim, and only a matching closer ends it.
        if (emitting) out.add(line);
        final trimmed = line.trimRight();
        final closer = _fence.firstMatch(trimmed);
        if (closer != null &&
            closer.group(2)![0] == fenceMarker &&
            closer.group(2)!.length >= fenceLength &&
            closer.group(3)!.trim().isEmpty) {
          fenceMarker = null;
          fenceLength = 0;
        }
        continue;
      }

      final opener = _fence.firstMatch(line.trimRight());
      if (opener != null) {
        fenceMarker = opener.group(2)![0];
        fenceLength = opener.group(2)!.length;
        if (emitting) out.add(line);
        continue;
      }

      final directive = _directive.firstMatch(line.trim());
      if (directive != null) {
        switch (directive.group(1)) {
          case 'if':
            final name = directive.group(2);
            if (name == null) {
              errors.add('`boost:if` without a flag name');
              stack.add(_Frame(parentEmitting: emitting, taken: true));
              emitting = false;
              break;
            }
            var value = flags.contains(name);
            if (!value && !knownFlag(name)) {
              unknownFlags.add(name);
              value = false;
            }
            stack.add(_Frame(parentEmitting: emitting, taken: value));
            emitting = emitting && value;
          case 'else':
            if (stack.isEmpty) {
              errors.add('`boost:else` outside any `boost:if`');
              break;
            }
            final frame = stack.last;
            emitting = frame.parentEmitting && !frame.taken;
          case 'end':
            if (stack.isEmpty) {
              errors.add('`boost:end` without a matching `boost:if`');
              break;
            }
            emitting = stack.removeLast().parentEmitting;
        }
        continue;
      }

      if (!emitting) continue;
      out.add(_substitute(line, variables, unknownVars));
    }

    if (stack.isNotEmpty) {
      errors.add('${stack.length} unterminated `boost:if` block(s)');
    }
    if (fenceMarker != null) {
      errors.add('unterminated fenced code block');
    }

    return RenderResult(
      content: out.join('\n'),
      unknownFlags: unknownFlags,
      unknownVars: unknownVars,
      errors: errors,
    );
  }

  String _substitute(
    String line,
    Map<String, String> variables,
    Set<String> unknownVars,
  ) => line.replaceAllMapped(_variable, (match) {
    final name = match.group(1)!;
    final value = variables[name];
    if (value == null) {
      unknownVars.add(name);
      return match.group(0)!;
    }
    return value;
  });
}

class _Frame {
  _Frame({required this.parentEmitting, required this.taken});

  /// Whether output was flowing when this `if` opened -- restored on `end`.
  final bool parentEmitting;

  /// Whether the `if` branch was taken, which is what `else` inverts.
  final bool taken;
}
