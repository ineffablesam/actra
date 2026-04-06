import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Word-by-word fade/slide reveal for **streaming** transcripts (Orion-style).
///
/// When the model **extends** the line, only new tail words animate. When it
/// **rewrites** (no shared word prefix), the full line is shown at once.
class RealtimeTypewriterTranscript extends StatefulWidget {
  const RealtimeTypewriterTranscript({
    super.key,
    required this.text,
    required this.style,
    required this.placeholderStyle,
    this.wordDelay = const Duration(milliseconds: 45),
    this.wrapAlignment = WrapAlignment.center,
    this.lineTextAlign = TextAlign.center,
    /// When false, an empty [text] renders nothing (e.g. chat bubbles before first chunk).
    /// When true (default), empty shows "Listening..." styling like the mic transcript.
    this.showListeningWhenEmpty = true,
  });

  final String text;
  final TextStyle style;
  final TextStyle placeholderStyle;
  final Duration wordDelay;
  final WrapAlignment wrapAlignment;
  final TextAlign lineTextAlign;
  final bool showListeningWhenEmpty;

  @override
  State<RealtimeTypewriterTranscript> createState() =>
      _RealtimeTypewriterTranscriptState();
}

class _RealtimeTypewriterTranscriptState
    extends State<RealtimeTypewriterTranscript> {
  static final _ws = RegExp(r'\s+');

  List<String> _words = [];
  List<bool> _shown = [];
  String _lastTranscriptWords = '';
  int _revealGen = 0;

  /// After a full rewrite, render one [Text] to avoid re-animating everything.
  bool _plainFullLine = false;

  /// Words before this index match the previous update — show without animation.
  int _instantPrefixLen = 0;

  bool _isPlaceholder(String t) => t.isEmpty || t == 'Listening...';

  @override
  void initState() {
    super.initState();
    _applyText(widget.text);
  }

  @override
  void didUpdateWidget(covariant RealtimeTypewriterTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _applyText(widget.text);
    }
  }

  void _applyText(String text) {
    if (_isPlaceholder(text)) {
      _revealGen++;
      setState(() {
        _words = [];
        _shown = [];
        _plainFullLine = false;
        _instantPrefixLen = 0;
      });
      return;
    }

    final newWords = text
        .trim()
        .split(_ws)
        .where((s) => s.isNotEmpty)
        .toList();
    final oldWords = _lastTranscriptWords
        .trim()
        .split(_ws)
        .where((s) => s.isNotEmpty)
        .toList();

    var lcp = 0;
    final n = oldWords.length < newWords.length ? oldWords.length : newWords.length;
    for (var i = 0; i < n; i++) {
      if (oldWords[i] == newWords[i]) {
        lcp++;
      } else {
        break;
      }
    }

    if (lcp == 0 && oldWords.isNotEmpty) {
      _revealGen++;
      setState(() {
        _words = newWords;
        _shown = List.filled(newWords.length, true);
        _plainFullLine = true;
        _instantPrefixLen = 0;
        _lastTranscriptWords = text;
      });
      return;
    }

    _revealGen++;
    final gen = _revealGen;

    setState(() {
      _plainFullLine = false;
      _words = newWords;
      _shown = List.generate(newWords.length, (i) => i < lcp);
      _instantPrefixLen = lcp;
      _lastTranscriptWords = text;
    });

    _revealTail(gen, lcp);
  }

  Future<void> _revealTail(int gen, int from) async {
    for (var i = from; i < _words.length; i++) {
      await Future<void>.delayed(widget.wordDelay);
      if (!mounted || gen != _revealGen) return;
      setState(() {
        if (i < _shown.length) _shown[i] = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty && !widget.showListeningWhenEmpty) {
      return const SizedBox.shrink();
    }

    if (_isPlaceholder(widget.text)) {
      return Text(
        widget.text.isEmpty ? 'Listening...' : widget.text,
        textAlign: widget.lineTextAlign,
        style: widget.placeholderStyle,
      );
    }

    if (_plainFullLine) {
      return _BlurRevealLine(
        key: ValueKey(widget.text),
        text: widget.text,
        style: widget.style,
        textAlign: widget.lineTextAlign,
      );
    }

    return Wrap(
      alignment: widget.wrapAlignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: List.generate(_words.length, (i) {
        final show = i < _shown.length && _shown[i];
        final chunk = _words[i] + (i == _words.length - 1 ? '' : ' ');
        final instant = i < _instantPrefixLen;

        if (!show) return const SizedBox.shrink();

        if (instant) {
          return Text(chunk, style: widget.style);
        }

        return _BlurRevealWord(
          key: ValueKey('anim-$i-$_revealGen-${_words[i]}'),
          text: chunk,
          style: widget.style,
        );
      }),
    );
  }
}

/// Gemini / Orion-style word reveal: blur clears, opacity and scale ease in.
class _BlurRevealWord extends StatelessWidget {
  const _BlurRevealWord({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return _blurRevealAnimation(
      duration: const Duration(milliseconds: 400),
      child: Text(text, style: style),
    );
  }
}

/// Same blur reveal for a full line when Whisper rewrites without a shared prefix.
class _BlurRevealLine extends StatelessWidget {
  const _BlurRevealLine({
    super.key,
    required this.text,
    required this.style,
    required this.textAlign,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return _blurRevealAnimation(
      duration: const Duration(milliseconds: 420),
      child: Text(
        text,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

Widget _blurRevealAnimation({
  required Duration duration,
  required Widget child,
}) {
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (context, t, _) {
      final blurSigma = 8.0 * (1.0 - t);
      return Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.95 + 0.05 * t,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
