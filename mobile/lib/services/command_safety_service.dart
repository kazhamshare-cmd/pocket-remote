import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dangerous command patterns to detect
final _dangerousPatterns = [
  // File deletion
  RegExp(r'\brm\s+(-[rRfF]+\s+|\s*)(/|~|\*)'),  // rm -rf /, rm -rf ~, rm *
  RegExp(r'\brm\s+-[rRfF]*\s+\S'),               // rm with force/recursive flags
  RegExp(r'>\s*/dev/s'),                         // Redirect to /dev/sda etc

  // System modification
  RegExp(r'\bsudo\s+rm\b'),                      // sudo rm
  RegExp(r'\bsudo\s+dd\b'),                      // sudo dd
  RegExp(r'\bsudo\s+mkfs\b'),                    // sudo mkfs
  RegExp(r'\bsudo\s+fdisk\b'),                   // sudo fdisk
  RegExp(r'\bsudo\s+chmod\s+777\b'),             // sudo chmod 777
  RegExp(r'\bsudo\s+chown\b'),                   // sudo chown

  // Git dangerous operations
  RegExp(r'\bgit\s+push\s+.*--force\b'),         // git push --force
  RegExp(r'\bgit\s+push\s+-f\b'),                // git push -f
  RegExp(r'\bgit\s+reset\s+--hard\b'),           // git reset --hard
  RegExp(r'\bgit\s+clean\s+-[dDfFxX]+\b'),       // git clean -fd

  // Database operations
  RegExp(r'\bDROP\s+(DATABASE|TABLE)\b', caseSensitive: false),
  RegExp(r'\bTRUNCATE\s+TABLE\b', caseSensitive: false),
  RegExp(r'\bDELETE\s+FROM\s+\w+\s*;?\s*$', caseSensitive: false),  // DELETE without WHERE

  // System commands
  RegExp(r'\bshutdown\b'),
  RegExp(r'\breboot\b'),
  RegExp(r'\bhalt\b'),
  RegExp(r'\bpoweroff\b'),
  RegExp(r'\bkillall\b'),
  RegExp(r'\bpkill\s+-9\b'),

  // Dangerous shell operations
  RegExp(r':\(\)\s*{\s*:\|:&\s*};\s*:'),         // Fork bomb
  RegExp(r'\beval\b.*\$'),                        // eval with variable
  RegExp(r'\bformat\s+[cC]:', caseSensitive: false),  // Windows format
];

/// Check if a command is potentially dangerous
bool isDangerousCommand(String command) {
  final trimmed = command.trim().toLowerCase();

  // Empty command is safe
  if (trimmed.isEmpty) return false;

  // Check against patterns
  for (final pattern in _dangerousPatterns) {
    if (pattern.hasMatch(command)) {
      return true;
    }
  }

  return false;
}

/// Get the danger level description
String getDangerReason(String command) {
  if (command.contains('rm') && (command.contains('-rf') || command.contains('-fr'))) {
    return 'Recursive forced deletion';
  }
  if (command.contains('sudo')) {
    return 'Administrator privileges required';
  }
  if (command.contains('git push') && (command.contains('--force') || command.contains('-f'))) {
    return 'Force push overwrites remote history';
  }
  if (command.contains('git reset --hard')) {
    return 'Discards all uncommitted changes';
  }
  if (RegExp(r'DROP|TRUNCATE|DELETE', caseSensitive: false).hasMatch(command)) {
    return 'Database modification';
  }
  if (command.contains('shutdown') || command.contains('reboot')) {
    return 'System power control';
  }
  return 'Potentially dangerous operation';
}

/// Command history and safe mode state
class CommandSafetyState {
  final bool safeModeEnabled;
  final List<String> commandHistory;
  final int maxHistorySize;

  CommandSafetyState({
    this.safeModeEnabled = true,
    this.commandHistory = const [],
    this.maxHistorySize = 50,
  });

  CommandSafetyState copyWith({
    bool? safeModeEnabled,
    List<String>? commandHistory,
    int? maxHistorySize,
  }) {
    return CommandSafetyState(
      safeModeEnabled: safeModeEnabled ?? this.safeModeEnabled,
      commandHistory: commandHistory ?? this.commandHistory,
      maxHistorySize: maxHistorySize ?? this.maxHistorySize,
    );
  }
}

class CommandSafetyService extends StateNotifier<CommandSafetyState> {
  CommandSafetyService() : super(CommandSafetyState()) {
    _loadSettings();
  }

  static const _safeModeKey = 'safe_mode_enabled';
  static const _historyKey = 'command_history';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final safeModeEnabled = prefs.getBool(_safeModeKey) ?? true;
    final history = prefs.getStringList(_historyKey) ?? [];

    state = state.copyWith(
      safeModeEnabled: safeModeEnabled,
      commandHistory: history,
    );
  }

  Future<void> setSafeMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_safeModeKey, enabled);
    state = state.copyWith(safeModeEnabled: enabled);
  }

  Future<void> addToHistory(String command) async {
    if (command.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final history = List<String>.from(state.commandHistory);

    // Remove if already exists (to move to top)
    history.remove(command);

    // Add to beginning
    history.insert(0, command);

    // Limit size
    while (history.length > state.maxHistorySize) {
      history.removeLast();
    }

    await prefs.setStringList(_historyKey, history);
    state = state.copyWith(commandHistory: history);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, []);
    state = state.copyWith(commandHistory: []);
  }

  Future<void> removeFromHistory(String command) async {
    final prefs = await SharedPreferences.getInstance();
    final history = List<String>.from(state.commandHistory);
    history.remove(command);
    await prefs.setStringList(_historyKey, history);
    state = state.copyWith(commandHistory: history);
  }
}

final commandSafetyProvider =
    StateNotifierProvider<CommandSafetyService, CommandSafetyState>((ref) {
  return CommandSafetyService();
});
