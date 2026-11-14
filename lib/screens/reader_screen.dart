import '../l10n/app_strings.dart';

import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_book.dart';
import '../audio/reading_player.dart';

class ReaderScreen extends StatefulWidget {
  final LocalBook book;
  final Uint8List? source;
  final bool listen;
  final Future<void> Function() persist;
  const ReaderScreen({
    super.key,
    required this.book,
    required this.source,
    required this.listen,
    required this.persist,
  });
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late final ReadingPlayer player;
  final PdfViewerController pdf = PdfViewerController();
  final ScrollController scroll = ScrollController();
  double font = 21;
  bool dark = false, pdfOriginal = true;
  String? selection;
  bool closing = false;
  Timer? saveTimer;
  String query = '';
  LocalBook get book => widget.book;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(trackScroll);
    player = ReadingPlayer(book, DeviceSpeech(), widget.persist)
      ..addListener(changed);
    unawaited(settings());
    restoreTextPosition();
    saveTimer = Timer.periodic(Duration(seconds: 5), (_) {
      unawaited(save());
    });
    if (widget.listen) unawaited(player.play());
  }

  TextPainter bodyPainter() => TextPainter(
    text: TextSpan(
      text: book.sections[book.section].text,
      style: TextStyle(fontSize: font, height: 1.9),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: math.min(720, MediaQuery.sizeOf(context).width - 48));
  double get bodyTop {
    final title = TextPainter(
      text: TextSpan(
        text: book.sections[book.section].title,
        style: TextStyle(fontSize: font + 4, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.min(720, MediaQuery.sizeOf(context).width - 48));
    final height = title.height;
    title.dispose();
    return 28 + height + 26;
  }

  bool positioning = false;
  void trackScroll() {
    if (positioning ||
        player.playing ||
        !scroll.hasClients ||
        book.format == 'pdf' && pdfOriginal) {
      return;
    }
    final painter = bodyPainter();
    final position = painter.getPositionForOffset(
      Offset(0, math.max(0, scroll.offset - bodyTop)),
    );
    painter.dispose();
    book.locate(book.section, position.offset);
  }

  void restoreTextPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !scroll.hasClients ||
          book.format == 'pdf' && pdfOriginal) {
        return;
      }
      final painter = bodyPainter();
      final point = painter.getOffsetForCaret(
        TextPosition(offset: book.offset),
        Rect.zero,
      );
      painter.dispose();
      positioning = true;
      scroll.jumpTo(
        (point.dy + bodyTop - 80).clamp(0, scroll.position.maxScrollExtent),
      );
      positioning = false;
    });
  }

  Future<void> settings() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        font = p.getDouble('reader_font') ?? 21;
        dark = p.getBool('reader_dark') ?? false;
      });
      restoreTextPosition();
    }
  }

  Future<void> save() async {
    try {
      await widget.persist();
    } catch (e) {
      if (mounted && !closing) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('保存进度失败：$e'))));
      }
    }
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (player.playing) restoreTextPosition();
    if (book.format == 'pdf' &&
        pdfOriginal &&
        pdf.isReady &&
        pdf.pageNumber != book.section + 1) {
      unawaited(pdf.goToPage(pageNumber: book.section + 1));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(save());
  }

  Future<void> leave() async {
    if (closing) return;
    closing = true;
    try {
      await player.pause();
      await widget.persist();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      closing = false;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('进度未能保存，请重试：$e'))));
      }
    }
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(changed);
    player.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> seek(int index, int offset) async {
    selection = null;
    await player.seek(index, offset);
    restoreTextPosition();
  }

  Future<void> contents() async {
    final index = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .75,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  context.tr('目录与章节'),
                  style: TextStyle(fontSize: 22),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: book.sections.length,
                  itemBuilder: (c, i) => ListTile(
                    selected: i == book.section,
                    title: Text(
                      book.sections[i].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: Text('${i + 1}'),
                    onTap: () => Navigator.pop(c, i),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (index != null) await seek(index, 0);
  }

  Future<void> search() async {
    final controller = TextEditingController(text: query);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('书内搜索')),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (s) => Navigator.pop(c, s),
          decoration: InputDecoration(hintText: context.tr('输入要查找的文字')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: Text(context.tr('搜索')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    query = value.trim();
    final hits = <({int section, int offset, String snippet})>[];
    for (var i = 0; i < book.sections.length; i++) {
      final text = book.sections[i].text;
      var offset = 0;
      while (offset < text.length && hits.length < 100) {
        final at = text.indexOf(query, offset);
        if (at < 0) break;
        hits.add((
          section: i,
          offset: at,
          snippet: text
              .substring(
                (at - 15).clamp(0, text.length),
                (at + query.length + 45).clamp(0, text.length),
              )
              .replaceAll('\n', ' '),
        ));
        offset = at + query.length;
      }
    }
    if (!mounted) return;
    final hit = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: hits.isEmpty
            ? Center(child: Text(context.tr('未找到文字；扫描 PDF 需要文本层')))
            : ListView.builder(
                itemCount: hits.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(hits[i].snippet),
                  subtitle: Text(book.sections[hits[i].section].title),
                  onTap: () => Navigator.pop(c, i),
                ),
              ),
      ),
    );
    if (hit != null) {
      pdfOriginal = false;
      await seek(hits[hit].section, hits[hit].offset);
    }
  }

  Future<void> options() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(context.tr('字号')),
                    Expanded(
                      child: Slider(
                        value: font,
                        min: 14,
                        max: 34,
                        divisions: 10,
                        onChanged: (v) {
                          setState(() => font = v);
                          update(() {});
                          unawaited(prefs.setDouble('reader_font', v));
                        },
                      ),
                    ),
                    Text('${font.round()}'),
                  ],
                ),
                SwitchListTile(
                  title: Text(context.tr('夜间阅读')),
                  value: dark,
                  onChanged: (v) {
                    setState(() => dark = v);
                    update(() {});
                    unawaited(prefs.setBool('reader_dark', v));
                  },
                ),
                DropdownButtonFormField<double>(
                  initialValue: player.speed,
                  decoration: InputDecoration(labelText: context.tr('朗读语速')),
                  items: [
                    DropdownMenuItem(value: .35, child: Text(context.tr('慢速'))),
                    DropdownMenuItem(value: .5, child: Text(context.tr('标准'))),
                    DropdownMenuItem(value: .65, child: Text(context.tr('快速'))),
                  ],
                  onChanged: (v) {
                    if (v != null) unawaited(player.setSpeed(v));
                  },
                ),
                ListTile(
                  title: Text(context.tr('选择系统声音')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(c);
                    unawaited(voices());
                  },
                ),
                SwitchListTile(
                  title: Text(context.tr('读完本节后停止')),
                  value: player.stopAtSection,
                  onChanged: (v) {
                    player.stopAtSection = v;
                    update(() {});
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final minutes in [0, 15, 30, 60])
                      ChoiceChip(
                        label: Text(
                          minutes == 0
                              ? context.tr('不定时')
                              : context.tr('$minutes 分钟'),
                        ),
                        selected: minutes == 0
                            ? player.sleepDeadline == null
                            : false,
                        onSelected: (_) {
                          player.sleep(minutes);
                          update(() {});
                        },
                      ),
                  ],
                ),
                if (player.sleepDeadline != null)
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      context.tr(
                        '停止时间 ${player.sleepDeadline!.hour.toString().padLeft(2, '0')}:${player.sleepDeadline!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
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
      if (!player.ready) await player.initialize();
      final voices = await player.engine.voices();
      if (!mounted) return;
      if (voices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('没有可用系统音色，请在系统中安装语音资源'))),
        );
        return;
      }
      final chosen = await showModalBottomSheet<Map<String, String>>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            children: voices
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('读取系统声音失败：$e'))));
      }
    }
  }

  Widget textView() {
    final text = book.sections[book.section].text;
    final offset = book.offset.clamp(0, text.length);
    return SingleChildScrollView(
      controller: scroll,
      padding: EdgeInsets.fromLTRB(24, 28, 24, 50),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.sections[book.section].title,
                style: TextStyle(
                  fontSize: font + 4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 26),
              if (text.isEmpty)
                Text(context.tr('此页没有可提取文本，可切换原版阅读。扫描件暂不支持朗读。'))
              else
                SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: text.substring(0, offset)),
                      TextSpan(
                        text: text.substring(offset),
                        style: TextStyle(
                          backgroundColor: player.playing
                              ? Color(0x225d8950)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: font, height: 1.9),
                  onSelectionChanged: (s, cause) {
                    if (s.isValid && !s.isCollapsed) {
                      selection = text.substring(s.start, s.end);
                      book.locate(book.section, s.start);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: dark ? ThemeData.dark(useMaterial3: true) : Theme.of(context),
    child: Builder(
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(leave());
        },
        child: Scaffold(
          backgroundColor: dark ? Color(0xff20251f) : Color(0xfff5f1e7),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              tooltip: context.tr('返回书架'),
              onPressed: leave,
              icon: Icon(Icons.arrow_back),
            ),
            title: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (book.format == 'pdf')
                IconButton(
                  tooltip: pdfOriginal
                      ? context.tr('切换文字／朗读视图')
                      : context.tr('切换 PDF 原版'),
                  onPressed: () => setState(() => pdfOriginal = !pdfOriginal),
                  icon: Icon(
                    pdfOriginal
                        ? Icons.text_fields
                        : Icons.picture_as_pdf_outlined,
                  ),
                ),
              IconButton(
                tooltip: context.tr('书内搜索'),
                onPressed: search,
                icon: Icon(Icons.search),
              ),
              IconButton(
                tooltip: context.tr('阅读与听书设置'),
                onPressed: options,
                icon: Icon(Icons.tune),
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
                      onPressed: () {
                        player.error = null;
                        unawaited(player.play());
                      },
                      child: Text(context.tr('重试')),
                    ),
                  ],
                ),
              Expanded(
                child:
                    book.format == 'pdf' && pdfOriginal && widget.source != null
                    ? PdfViewer.data(
                        widget.source!,
                        sourceName: book.id,
                        controller: pdf,
                        initialPageNumber: book.section + 1,
                        params: PdfViewerParams(
                          onPageChanged: (page) {
                            if (page != null && page != book.section + 1) {
                              unawaited(seek(page - 1, 0));
                            }
                          },
                        ),
                      )
                    : textView(),
              ),
              SafeArea(
                top: false,
                child: Container(
                  color: dark ? Color(0xff2d342b) : Colors.white70,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: context.tr('目录'),
                            onPressed: contents,
                            icon: Icon(Icons.list),
                          ),
                          Expanded(
                            child: Slider(
                              value: book.section.toDouble(),
                              min: 0,
                              max: (book.sections.length - 1)
                                  .clamp(1, 100000)
                                  .toDouble(),
                              onChanged: (v) => unawaited(
                                seek(
                                  v.round().clamp(0, book.sections.length - 1),
                                  0,
                                ),
                              ),
                            ),
                          ),
                          Text('${book.section + 1}/${book.sections.length}'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: context.tr('上一节'),
                            onPressed: book.section > 0
                                ? () => seek(book.section - 1, 0)
                                : null,
                            icon: Icon(Icons.skip_previous),
                          ),
                          FilledButton.icon(
                            onPressed: book.readable
                                ? () {
                                    if (player.playing) {
                                      unawaited(player.pause());
                                    } else {
                                      if (book.format == 'pdf') {
                                        setState(() => pdfOriginal = false);
                                      }
                                      unawaited(player.play());
                                    }
                                  }
                                : null,
                            icon: Icon(
                              player.playing
                                  ? Icons.pause
                                  : Icons.headphones_outlined,
                            ),
                            label: Text(
                              player.playing
                                  ? context.tr('暂停听书')
                                  : context.tr('从当前位置听书'),
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr('下一节'),
                            onPressed: book.section < book.sections.length - 1
                                ? () => seek(book.section + 1, 0)
                                : null,
                            icon: Icon(Icons.skip_next),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
