/// A model result is kept separate from the source book and reading position.
class ParagraphLesson {
  final String translation;
  final String background;
  final String sourceLanguage;
  const ParagraphLesson({
    required this.translation,
    this.background = '',
    this.sourceLanguage = 'en',
  });
}

abstract interface class ParagraphTranslator {
  Future<ParagraphLesson> translate({
    required String original,
    required String targetLanguage,
    required String bookTitle,
    required String chapterTitle,
    required bool includeBackground,
  });
}
