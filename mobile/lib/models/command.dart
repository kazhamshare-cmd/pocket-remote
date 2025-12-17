class Command {
  final String id;
  final String name;
  final String command;
  final String? icon;

  Command({
    required this.id,
    required this.name,
    required this.command,
    this.icon,
  });

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'icon': icon,
    };
  }
}
