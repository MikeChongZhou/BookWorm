import 'dart:convert';
import 'dart:typed_data';

class BookSection {
  final String title;
  final String text;
  const BookSection(this.title, this.text);
  Map<String, dynamic> toJson() => {'title': title, 'text': text};
  factory BookSection.fromJson(Map<String, dynamic> j) =>
      BookSection(j['title'] as String, j['text'] as String);
}

class LocalBook {
  final String id;
  String title;
  final String author, format;
  final List<BookSection> sections;
  final Uint8List? cover;
  int audioOffsetMs;
  int section, offset, modified;
  LocalBook({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.sections,
    this.cover,
    this.audioOffsetMs = 0,
    this.section = 0,
    this.offset = 0,
    int? modified,
  }) : modified = modified ?? DateTime.now().millisecondsSinceEpoch;
  double get progress => sections.isEmpty
      ? 0
      : (section + offset / (sections[section].text.length + 1)) /
            sections.length;
  bool get readable => sections.any((s) => s.text.trim().isNotEmpty);
  void locate(int page, int character) {
    section = page.clamp(0, sections.length - 1);
    offset = character.clamp(0, sections[section].text.length);
    modified = DateTime.now().millisecondsSinceEpoch;
    audioOffsetMs = 0;
  }

  Map<String, dynamic> toJson() => {
    'schema': 3,
    'id': id,
    'title': title,
    'author': author,
    'format': format,
    if (cover != null) 'cover': base64Encode(cover!),
    'audioOffsetMs': audioOffsetMs,
    'sections': sections.map((s) => s.toJson()).toList(),
    'section': section,
    'offset': offset,
    'modified': modified,
  };
  Map<String, dynamic> position() => {
    'schema': 1,
    'id': id,
    'section': section,
    'offset': offset,
    'modified': modified,
    'audioOffsetMs': audioOffsetMs,
  };
  factory LocalBook.fromJson(Map<String, dynamic> j) {
    final sections = (j['sections'] as List)
        .map((s) => BookSection.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    if (sections.isEmpty) throw const FormatException('书籍没有内容或页面');
    final b = LocalBook(
      id: j['id'] as String,
      title: j['title'] as String,
      author: j['author'] as String,
      format: j['format'] as String,
      cover: j['cover'] is String ? base64Decode(j['cover']) : null,
      audioOffsetMs: (j['audioOffsetMs'] as int?) ?? 0,
      sections: sections,
      modified: j['modified'] as int?,
    );
    b.section = ((j['section'] as int?) ?? 0).clamp(0, sections.length - 1);
    b.offset = ((j['offset'] as int?) ?? 0).clamp(
      0,
      sections[b.section].text.length,
    );
    return b;
  }
}
