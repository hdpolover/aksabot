import 'package:flutter/material.dart';

/// Integrations management screen — planned UI (future).
class IntegrationsPage extends StatelessWidget {
  final String deviceId;
  const IntegrationsPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connected
          Text('Connected', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.cloud, color: colors.primary),
              title: const Text('Weather'),
              subtitle: const Text('OpenWeatherMap'),
              value: true,
              onChanged: (_) {},
            ),
          ),
          const SizedBox(height: 24),

          // Available
          Text('Available', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _IntegrationTile(
                  icon: Icons.calendar_today,
                  name: 'Google Calendar',
                  description: 'Morning briefing, events',
                  color: colors.primary,
                ),
                const Divider(height: 1),
                _IntegrationTile(
                  icon: Icons.newspaper,
                  name: 'News',
                  description: 'Headlines in briefing',
                  color: colors.tertiary,
                ),
                const Divider(height: 1),
                _IntegrationTile(
                  icon: Icons.home,
                  name: 'Home Assistant',
                  description: 'Smart home voice control',
                  color: colors.secondary,
                ),
                const Divider(height: 1),
                _IntegrationTile(
                  icon: Icons.music_note,
                  name: 'Spotify',
                  description: 'Music control via voice',
                  color: Colors.green,
                ),
                const Divider(height: 1),
                _IntegrationTile(
                  icon: Icons.checklist,
                  name: 'Todoist',
                  description: 'Task management via voice',
                  color: Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Integrations let Aksa access external services to give you '
            'richer responses and control.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final Color color;

  const _IntegrationTile({
    required this.icon,
    required this.name,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(name),
      subtitle: Text(description),
      trailing: FilledButton.tonal(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name integration coming soon')),
          );
        },
        child: const Text('Connect'),
      ),
    );
  }
}
