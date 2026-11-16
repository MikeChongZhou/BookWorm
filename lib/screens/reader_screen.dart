import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/book_audio_handler.dart';
import '../audio/reading_player.dart';
import '../audio/melo_speech.dart';
import '../audio/chapter_timeline.dart';
import '../models/local_book.dart';
import '../l10n/app_strings.dart';

class ReaderScreen extends StatefulWidget {
  final LocalBook book;
  final Uint8List? source;
  final bool listen;
  final bool? autoPlay;
  final Future<void> Function() persist;
  final SpeechEngine? speechEngine;
  const ReaderScreen({
    super.key,
    required this.book,
    required this.source,
    required this.listen,
    this.autoPlay,
    required this.persist,
    this.speechEngine,
  });
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late final ReadingPlayer player;
  final PdfViewerController pdf = PdfViewerController();
  late bool listening;
  bool toolbar = false, followAudio = true, closing = false, foreground = true;
  bool pdfOriginal = true, turning = false, highlight = false;
  double font = 21;
  Color paper = const Color(0xfff5f1e7), ink = const Color(0xff262a26);
  List<SpeechSpan> pages = [];
  String pageKey = '';
  int page = 0;
  Timer? autoPage;
  int autoSeconds = 15;
  double? scrub;
  String? noteQuote;
  LocalBook get book => player.book;
  @override
  void initState() {
    super.initState();
    listening = widget.listen;
    highlight = widget.listen;
    WidgetsBinding.instance.addObserver(this);
    final existing = widget.speechEngine == null
        ? BookAudioHandler.instance?.player
        : null;
    player =
        existing != null &&
            existing.book.id == widget.book.id &&
            !existing.disposed
        ? existing
        : ReadingPlayer(
            widget.book,
            widget.speechEngine ?? SelectedSpeech(),
            widget.persist,
          );
    player.addListener(changed);
    unawaited(_loadSettings());
    unawaited(_attach());
  }

  Future<void> _attach() async {
    try {
      if (widget.speechEngine == null) {
        await BookAudioHandler.instance?.attach(player);
      }
      if ((widget.autoPlay ?? widget.listen) && mounted) {
        unawaited(player.play());
      }
    } catch (e) {
      if (mounted) setState(() => player.error = '听书初始化失败：$e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      font = (prefs.getDouble('reader_font') ?? 21).clamp(14, 40);
      paper = Color(
        prefs.getInt('reader_paper') ??
            (prefs.getBool('reader_dark') == true ? 0xff20251f : 0xfff5f1e7),
      );
      ink = Color(
        prefs.getInt('reader_ink') ??
            (prefs.getBool('reader_dark') == true ? 0xffe6e7de : 0xff262a26),
      );
      autoSeconds = prefs.getInt('reader_auto_seconds') ?? 15;
    });
  }

  void changed() {
    if (!mounted) return;
    if (player.playing) highlight = true;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    // Locking the screen saves progress; it must never pause the audio session.
    if (!foreground) unawaited(player.persist());
  }

  Future<void> leave() async {
    if (closing) return;
    closing = true;
    try {
      await player.persist();
      if (!player.ready && !player.playing && !player.buffering) {
        await BookAudioHandler.instance?.detach(player);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      closing = false;
      if (mounted) message('进度未能保存，请重试：$e');
    }
  }

  @override
  void dispose() {
    autoPage?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(changed);
    if (!identical(BookAudioHandler.instance?.player, player)) player.dispose();
    super.dispose();
  }

  void message(String text) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr(text))));
  Future<void> toggle() async {
    if (player.playing || player.buffering) {
      await player.pause();
    } else {
      highlight = true;
      followAudio = true;
      unawaited(player.play());
    }
  }

  Future<void> seek(int section, int offset) async {
    followAudio = true;
    pageKey = '';
    await player.seek(section, offset);
  }

  Future<void> contents() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.tr('目录与章节'),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: book.sections.length,
                  itemBuilder: (c, i) => ListTile(
                    selected: i == book.section,
                    leading: Text('${i + 1}'),
                    title: Text(
                      book.sections[i].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(c, i),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) await seek(selected, 0);
  }

  Future<void> timerOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('定时停止'),
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in [0, 15, 30, 45, 60, 90])
                      ActionChip(
                        label: Text(
                          m == 0 ? context.tr('不定时') : context.tr('$m 分钟'),
                        ),
                        onPressed: () {
                          player.sleep(m);
                          Navigator.pop(c);
                        },
                      ),
                  ],
                ),
                SwitchListTile(
                  title: Text(context.tr('读完本章后停止')),
                  value: player.stopAtSection,
                  onChanged: (value) {
                    player.stopAtSection = value;
                    update(() {});
                  },
                ),
                if (player.sleepDeadline != null)
                  Text(
                    '${context.tr('停止时间')} ${TimeOfDay.fromDateTime(player.sleepDeadline!).format(context)}',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> voices() async {
    try {
      await player.initialize();
      final values = await player.engine.voices();
      if (!mounted) return;
      if (values.isEmpty) {
        message('没有可用系统音色，请在系统中安装语音资源');
        return;
      }
      final chosen = await showModalBottomSheet<Map<String, String>>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(
            children: values
                .map(
                  (v) => ListTile(
                    title: Text(v['name'] ?? context.tr('系统语音')),
                    subtitle: Text(v['locale'] ?? ''),
                    onTap: () => Navigator.pop(c, v),
                  ),
                )
                .toList(),
          ),
        ),
      );
      if (chosen != null) await player.setVoice(chosen);
    } catch (e) {
      if (mounted) message('读取系统声音失败：$e');
    }
  }

  Future<void> speeds() async {
    final value = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final rate in [.7, .8, .9, 1.0, 1.1, 1.2])
              ListTile(
                title: Text('${rate.toStringAsFixed(1)}×'),
                selected: (player.speed * 2 - rate).abs() < .01,
                onTap: () => Navigator.pop(c, rate),
              ),
          ],
        ),
      ),
    );
    if (value != null) {
      try {
        await player.setSpeed(value / 2);
      } catch (e) {
        if (mounted) message('$e');
      }
    }
  }

  Future<void> fonts() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${context.tr('字体大小')} · ${font.round()}',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                Slider(
                  value: font,
                  min: 14,
                  max: 40,
                  divisions: 26,
                  onChanged: (v) {
                    setState(() {
                      font = v;
                      pageKey = '';
                    });
                    update(() {});
                    unawaited(
                      SharedPreferences.getInstance().then(
                        (p) => p.setDouble('reader_font', v),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> colors() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('背景颜色'),
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final value in [
                      0xfff5f1e7,
                      0xffffffff,
                      0xffdce9d6,
                      0xffe7e5ef,
                      0xff20251f,
                      0xff101010,
                    ])
                      colorButton(Color(value), paper, () {
                        setState(() => paper = Color(value));
                        update(() {});
                        unawaited(
                          SharedPreferences.getInstance().then(
                            (p) => p.setInt('reader_paper', value),
                          ),
                        );
                      }),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  context.tr('字体颜色'),
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final value in [
                      0xff262a26,
                      0xff000000,
                      0xffe6e7de,
                      0xff644635,
                      0xff234b69,
                      0xff48664e,
                    ])
                      colorButton(Color(value), ink, () {
                        setState(() => ink = Color(value));
                        update(() {});
                        unawaited(
                          SharedPreferences.getInstance().then(
                            (p) => p.setInt('reader_ink', value),
                          ),
                        );
                      }),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget colorButton(Color color, Color selected, VoidCallback action) =>
      Semantics(
        label: color.toARGB32().toRadixString(16),
        selected: color == selected,
        button: true,
        child: InkWell(
          onTap: action,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: color == selected ? Colors.orange : Colors.grey,
                width: color == selected ? 3 : 1,
              ),
            ),
          ),
        ),
      );
  Future<void> autoOptions() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.tr('关闭自动翻页')),
              onTap: () => Navigator.pop(c, 0),
            ),
            for (final seconds in [5, 10, 15, 20, 30, 60])
              ListTile(
                title: Text(context.tr('每 $seconds 秒翻页')),
                selected: autoPage != null && autoSeconds == seconds,
                onTap: () => Navigator.pop(c, seconds),
              ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    autoPage?.cancel();
    autoPage = null;
    if (value > 0) {
      await player.pause();
      autoSeconds = value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reader_auto_seconds', value);
      autoPage = Timer.periodic(Duration(seconds: value), (_) {
        if (foreground &&
            !listening &&
            !player.playing &&
            mounted &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          unawaited(turnPage(1));
        }
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> notes() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bookworm_notes_${book.id}';
    var values = (prefs.getStringList(key) ?? [])
        .map((s) => Map<String, dynamic>.from(jsonDecode(s)))
        .toList();
    if (!mounted) return;
    final input = TextEditingController();
    final quote =
        noteQuote ??
        book.sections[book.section].text.substring(
          player.sentence.start,
          player.sentence.end,
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(c).bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(c).height * .65,
              child: Column(
                children: [
                  Text(
                    context.tr('本地笔记'),
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  Text(quote, maxLines: 3, overflow: TextOverflow.ellipsis),
                  TextField(
                    controller: input,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: context.tr('写下笔记')),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () async {
                        if (input.text.trim().isEmpty) return;
                        final next = [
                          ...values,
                          {
                            'quote': quote,
                            'text': input.text.trim(),
                            'section': book.section,
                            'offset': book.offset,
                          },
                        ];
                        try {
                          if (!await prefs.setStringList(
                            key,
                            next.map(jsonEncode).toList(),
                          )) {
                            throw StateError('保存失败');
                          }
                          values = next;
                          input.clear();
                          update(() {});
                        } catch (e) {
                          if (mounted) message('保存笔记失败：$e');
                        }
                      },
                      child: Text(context.tr('保存')),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: values.reversed
                          .map(
                            (n) => ListTile(
                              title: Text(n['text']),
                              subtitle: Text(
                                n['quote'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(c);
                                unawaited(seek(n['section'], n['offset']));
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    input.dispose();
    noteQuote = null;
  }

  Future<void> search() async {
    final input = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('书内搜索')),
        content: TextField(
          controller: input,
          autofocus: true,
          onSubmitted: (s) => Navigator.pop(c, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: Text(context.tr('搜索')),
          ),
        ],
      ),
    );
    input.dispose();
    if (query == null || query.trim().isEmpty || !mounted) return;
    final hits = <(int, int, String)>[];
    for (var i = 0; i < book.sections.length && hits.length < 100; i++) {
      final text = book.sections[i].text;
      var cursor = 0;
      while (hits.length < 100) {
        final at = text.indexOf(query.trim(), cursor);
        if (at < 0) break;
        hits.add((
          i,
          at,
          text.substring(
            math.max(0, at - 15),
            math.min(text.length, at + query.length + 40),
          ),
        ));
        cursor = at + query.length;
      }
    }
    final hit = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: hits.isEmpty
            ? Center(child: Text(context.tr('未找到文字；扫描 PDF 需要文本层')))
            : ListView.builder(
                itemCount: hits.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(hits[i].$3),
                  subtitle: Text(book.sections[hits[i].$1].title),
                  onTap: () => Navigator.pop(c, i),
                ),
              ),
      ),
    );
    if (hit != null && mounted) {
      setState(() {
        listening = false;
        pdfOriginal = false;
      });
      await seek(hits[hit].$1, hits[hit].$2);
    }
  }

  Future<void> showOriginal() async {
    setState(() {
      listening = false;
      pdfOriginal = false;
      followAudio = true;
      highlight = true;
      toolbar = false;
      pageKey = '';
    });
  }

  Future<void> showPlayer() async {
    autoPage?.cancel();
    autoPage = null;
    setState(() {
      listening = true;
      toolbar = false;
    });
    if (!player.playing && !player.buffering) unawaited(player.play());
  }

  static String clock(Duration value) {
    final seconds = math.max(0, value.inSeconds);
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget listeningView() => LayoutBuilder(
    builder: (context, size) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            children: [
              BookCover(
                book: book,
                height: (size.maxHeight * .36).clamp(110, 280),
              ),
              const SizedBox(height: 24),
              Text(
                book.sections[book.section].title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(
                  '第 ${book.section + 1} 章 · 共 ${book.sections.length} 章',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: timerOptions,
                    icon: const Icon(Icons.timer_outlined),
                    label: Text(
                      context.tr(player.sleepDeadline == null ? '定时' : '已定时'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: voices,
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: Text(context.tr('声音')),
                  ),
                  TextButton.icon(
                    onPressed: speeds,
                    icon: const Icon(Icons.speed),
                    label: Text('${(player.speed * 2).toStringAsFixed(1)}×'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: context.tr('回退20秒'),
                    onPressed: () => player.jump(-20),
                    icon: const Icon(Icons.replay, size: 30),
                  ),
                  const Text('20'),
                  Expanded(
                    child: Slider(
                      value:
                          (scrub ?? player.position.inMilliseconds.toDouble())
                              .clamp(
                                0,
                                math
                                    .max(1, player.duration.inMilliseconds)
                                    .toDouble(),
                              ),
                      min: 0,
                      max: math
                          .max(1, player.duration.inMilliseconds)
                          .toDouble(),
                      onChanged: (value) => setState(() => scrub = value),
                      onChangeEnd: (value) {
                        scrub = null;
                        unawaited(
                          player.seekTime(
                            Duration(milliseconds: value.round()),
                          ),
                        );
                      },
                    ),
                  ),
                  const Text('20'),
                  IconButton(
                    tooltip: context.tr('快进20秒'),
                    onPressed: () => player.jump(20),
                    icon: const Icon(Icons.forward_rounded, size: 30),
                  ),
                ],
              ),
              Text(
                '${clock(Duration(milliseconds: scrub?.round() ?? player.position.inMilliseconds))} / ${clock(player.duration)}${player.durationExact ? '' : ' · ${context.tr('预计')}'}',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(height: size.maxHeight < 600 ? 20 : 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  control(Icons.subject, '原文', showOriginal),
                  IconButton(
                    tooltip: context.tr('回退一章'),
                    onPressed: book.section > 0
                        ? () => seek(book.section - 1, 0)
                        : null,
                    icon: const Icon(Icons.skip_previous_rounded, size: 36),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                    ),
                    onPressed: book.readable ? toggle : null,
                    child: Icon(
                      player.playing || player.buffering
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 40,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('前进一章'),
                    onPressed: book.section + 1 < book.sections.length
                        ? () => seek(book.section + 1, 0)
                        : null,
                    icon: const Icon(Icons.skip_next_rounded, size: 36),
                  ),
                  control(Icons.format_list_bulleted, '目录', contents),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget control(IconData icon, String label, VoidCallback action) => Semantics(
    button: true,
    label: context.tr(label),
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(context.tr(label), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );

  void paginate(Size size, TextScaler scaler) {
    final key =
        '${book.section}/${size.width}/${size.height}/$font/${scaler.scale(font)}';
    if (pageKey == key) return;
    pageKey = key;
    final text = book.sections[book.section].text;
    pages = paginateChapter(
      text,
      TextStyle(fontSize: font, height: 1.8),
      size,
      scaler,
    );
    page = pages
        .indexWhere((p) => book.offset < p.end)
        .clamp(0, pages.length - 1);
  }

  Future<void> turnPage(int direction) async {
    if (turning || listening) return;
    turning = true;
    followAudio = false;
    await player.pause();
    try {
      final next = page + direction;
      if (next >= 0 && next < pages.length) {
        await player.seek(book.section, pages[next].start);
        if (mounted) setState(() => page = next);
      } else if (direction > 0 && book.section + 1 < book.sections.length) {
        pageKey = '';
        await player.seek(book.section + 1, 0);
      } else if (direction < 0 && book.section > 0) {
        pageKey = '';
        await player.seek(
          book.section - 1,
          book.sections[book.section - 1].text.length - 1,
        );
      } else {
        autoPage?.cancel();
        autoPage = null;
      }
    } finally {
      turning = false;
    }
  }

  Widget originalView() => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(720.0, constraints.maxWidth - 40);
      final height = math.max(40.0, constraints.maxHeight - 96);
      final scaler = MediaQuery.textScalerOf(context);
      paginate(Size(width, height), scaler);
      if (followAudio && player.playing) {
        final target = pages.indexWhere((p) => book.offset < p.end);
        if (target >= 0) page = target;
      }
      final slice = pages[page];
      final text = book.sections[book.section].text;
      final sentence = player.sentence;
      final start = sentence.start.clamp(slice.start, slice.end),
          end = sentence.end.clamp(slice.start, slice.end);
      final style = TextStyle(fontSize: font, height: 1.8, color: ink);
      final spans = TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(slice.start, start)),
          TextSpan(
            text: text.substring(start, end),
            style: highlight
                ? TextStyle(
                    backgroundColor: paper.computeLuminance() > .4
                        ? const Color(0xffd7d7d2)
                        : const Color(0xff555853),
                  )
                : null,
          ),
          TextSpan(text: text.substring(end, slice.end)),
        ],
      );
      return Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            unawaited(turnPage(event.scrollDelta.dy < 0 ? -1 : 1));
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0).abs() > 50) {
              unawaited(turnPage(d.primaryVelocity! < 0 ? -1 : 1));
            }
          },
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0).abs() > 50) {
              unawaited(turnPage(d.primaryVelocity! < 0 ? -1 : 1));
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Text(
                  book.sections[book.section].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.withValues(alpha: .65),
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) async {
                        final painter = TextPainter(
                          text: spans,
                          textDirection: TextDirection.ltr,
                          textScaler: scaler,
                        )..layout(maxWidth: width);
                        final offset =
                            painter
                                .getPositionForOffset(details.localPosition)
                                .offset +
                            slice.start;
                        final boxes = painter.getBoxesForSelection(
                          TextSelection(
                            baseOffset: 0,
                            extentOffset: slice.end - slice.start,
                          ),
                        );
                        final onText = boxes.any(
                          (box) => box.toRect().contains(details.localPosition),
                        );
                        painter.dispose();
                        if (highlight &&
                            onText &&
                            offset >= sentence.start &&
                            offset < sentence.end) {
                          followAudio = false;
                          await player.pause();
                        } else {
                          setState(() => toolbar = !toolbar);
                        }
                      },
                      onLongPress: () {
                        noteQuote = text.substring(slice.start, slice.end);
                        unawaited(notes());
                      },
                      child: RichText(
                        text: spans,
                        textScaler: scaler,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  '${page + 1} / ${pages.length} · ${context.tr('第 ${book.section + 1} 章')}',
                  style: TextStyle(
                    color: ink.withValues(alpha: .6),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget readingToolbar() => SafeArea(
    top: false,
    child: Material(
      color: paper,
      elevation: 8,
      child: SizedBox(
        height: 78,
        child: IconTheme(
          data: IconThemeData(color: ink),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: ink),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                control(Icons.play_circle_outline, '播放', showPlayer),
                control(Icons.list, '目录', contents),
                control(Icons.edit_note, '笔记', notes),
                control(
                  autoPage == null
                      ? Icons.auto_stories_outlined
                      : Icons.pause_circle_outline,
                  '自动翻页',
                  autoOptions,
                ),
                control(Icons.palette_outlined, '颜色', colors),
                control(Icons.format_size, '字号', fonts),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(leave());
    },
    child: Scaffold(
      backgroundColor: listening
          ? Theme.of(context).scaffoldBackgroundColor
          : paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: listening ? null : ink,
        leading: IconButton(
          tooltip: context.tr('返回书架'),
          onPressed: leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (book.format == 'pdf' && !listening)
            IconButton(
              tooltip: context.tr('切换文字／朗读视图'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => setState(() => pdfOriginal = !pdfOriginal),
            ),
          IconButton(
            tooltip: context.tr('书内搜索'),
            onPressed: search,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          if (player.error != null)
            MaterialBanner(
              content: Text(player.error!),
              actions: [
                TextButton(
                  onPressed: () => unawaited(player.play()),
                  child: Text(context.tr('重试')),
                ),
              ],
            ),
          if (player.buffering)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(context.tr('正在准备语音…')),
                ],
              ),
            ),
          Expanded(
            child: listening
                ? listeningView()
                : book.format == 'pdf' && pdfOriginal && widget.source != null
                ? PdfViewer.data(
                    widget.source!,
                    sourceName: book.id,
                    controller: pdf,
                    initialPageNumber: book.section + 1,
                    params: PdfViewerParams(
                      onPageChanged: (p) {
                        if (p != null && p - 1 != book.section) {
                          unawaited(player.seek(p - 1, 0));
                        }
                      },
                    ),
                  )
                : originalView(),
          ),
        ],
      ),
      bottomNavigationBar: !listening && toolbar ? readingToolbar() : null,
    ),
  );
}

List<SpeechSpan> paginateChapter(
  String text,
  TextStyle style,
  Size size,
  TextScaler scaler,
) {
  if (text.isEmpty) return [const SpeechSpan(0, 0)];
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: size.width);
  final result = <SpeechSpan>[];
  var start = 0;
  var top = 0.0;
  for (final line in painter.computeLineMetrics()) {
    if (line.baseline + line.descent - top <= size.height) continue;
    final at = painter
        .getPositionForOffset(Offset(0, line.baseline - line.ascent / 2))
        .offset;
    if (at > start) {
      result.add(SpeechSpan(start, at));
      start = at;
      top = line.baseline - line.ascent;
    }
  }
  result.add(SpeechSpan(start, text.length));
  painter.dispose();
  return result;
}

class BookCover extends StatelessWidget {
  final LocalBook book;
  final double height;
  const BookCover({super.key, required this.book, this.height = 240});
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: height * .7,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xffdce2d2),
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: book.cover == null
        ? fallback()
        : Image.memory(
            book.cover!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, e, stack) => fallback(),
          ),
  );
  Widget fallback() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.menu_book_outlined, color: Color(0xff48664e)),
        const Spacer(),
        Text(
          book.title,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xff26382b),
            fontSize: (height / 10).clamp(16, 28),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          book.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xff48664e), fontSize: 12),
        ),
      ],
    ),
  );
}
