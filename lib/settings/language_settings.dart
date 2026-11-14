import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageSettings extends ChangeNotifier {
  static const supported = ['system', 'zh', 'en', 'es'];
  String _value = 'system';
  String get value => _value;
  Locale? get locale => _value == 'system' ? null : Locale(_value);
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('bookworm_language');
    _value = supported.contains(saved) ? saved! : 'system';
    notifyListeners();
  }

  Future<void> select(String value) async {
    if (!supported.contains(value)) throw ArgumentError.value(value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('bookworm_language', value)) {
      throw StateError('Could not save app language');
    }
    _value = value;
    notifyListeners();
  }
}

class LanguageScope extends InheritedNotifier<LanguageSettings> {
  const LanguageScope({
    super.key,
    required LanguageSettings settings,
    required super.child,
  }) : super(notifier: settings);
  static LanguageSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
}
