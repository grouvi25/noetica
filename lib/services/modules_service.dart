import 'package:shared_preferences/shared_preferences.dart';

const _kModulesKey = 'noetica.activeModules';

/// App modules that can be toggled on/off in Settings.
enum AppModule {
  reflection('Рефлексия', '📝', 'Ежедневный журнал', true),
  coach('AI-Коуч', '🤖', 'Персональный коучинг', false),
  analytics('Аналитика', '📊', 'Графики и тренды', false),
  knowledge('База знаний', '🧠', 'Граф + заметки', false),
  focus('Фокус', '⏱', 'Pomodoro-таймер', false),
  habits('Привычки', '🔄', 'Трекер привычек', false);

  const AppModule(this.title, this.icon, this.description, this.enabledByDefault);
  final String title;
  final String icon;
  final String description;
  final bool enabledByDefault;
}

/// Persists enabled/disabled module state to SharedPreferences.
class ModulesService {
  static final ModulesService instance = ModulesService._();
  ModulesService._();

  Future<Set<AppModule>> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kModulesKey);
    if (saved == null) {
      return AppModule.values.where((m) => m.enabledByDefault).toSet();
    }
    return saved
        .map((name) {
          try {
            return AppModule.values.byName(name);
          } catch (_) {
            return null;
          }
        })
        .whereType<AppModule>()
        .toSet();
  }

  Future<void> saveActive(Set<AppModule> modules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kModulesKey,
      modules.map((m) => m.name).toList(),
    );
  }

  Future<void> toggle(AppModule module, bool enabled) async {
    final current = await loadActive();
    if (enabled) {
      current.add(module);
    } else {
      current.remove(module);
    }
    await saveActive(current);
  }

  Future<bool> isEnabled(AppModule module) async {
    final active = await loadActive();
    return active.contains(module);
  }
}
