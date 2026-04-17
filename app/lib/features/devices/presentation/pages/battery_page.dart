import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../data/models/device_stats_model.dart';
import '../../domain/repositories/devices_repository.dart';

/// Dedicated battery detail page — drill-down from the Device Detail page.
///
/// Shows the full battery history (including charging segments, which the
/// inline detail-page chart filters out), interactive chart with tap-to-read,
/// a time-range selector, summary metrics, and a raw history list.
class BatteryPage extends StatefulWidget {
  final String deviceId;
  const BatteryPage({super.key, required this.deviceId});

  @override
  State<BatteryPage> createState() => _BatteryPageState();
}

enum _Range { h1, h6, h24, all }

extension on _Range {
  String get label => switch (this) {
        _Range.h1 => '1h',
        _Range.h6 => '6h',
        _Range.h24 => '24h',
        _Range.all => 'All',
      };

  Duration? get duration => switch (this) {
        _Range.h1 => const Duration(hours: 1),
        _Range.h6 => const Duration(hours: 6),
        _Range.h24 => const Duration(hours: 24),
        _Range.all => null,
      };
}

class _BatteryPageState extends State<BatteryPage> {
  final _devicesRepo = sl<DevicesRepository>();

  DeviceStats? _stats;
  String? _error;
  bool _loading = true;
  Timer? _refreshTimer;
  _Range _range = _Range.all;
  bool _showRawLog = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Refresh every 30s so the page shows live data while open.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetch(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final result = await _devicesRepo.getStats(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (json) => setState(() {
        _stats = DeviceStats.fromJson(json);
        _error = null;
        _loading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetch,
          ),
        ],
      ),
      body: _loading && _stats == null
          ? const AppLoadingIndicator()
          : _error != null && _stats == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: cs.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: _fetch,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.all(AppConstants.spacingLg),
                    children: [
                      _HeaderCard(stats: _stats!),
                      const SizedBox(height: AppConstants.spacingLg),
                      _RangeSelector(
                        current: _range,
                        onChanged: (r) => setState(() => _range = r),
                      ),
                      const SizedBox(height: AppConstants.spacingMd),
                      _ChartCard(
                        stats: _stats!,
                        range: _range,
                      ),
                      const SizedBox(height: AppConstants.spacingLg),
                      _MetricsCard(stats: _stats!, range: _range),
                      const SizedBox(height: AppConstants.spacingLg),
                      _RawLogCard(
                        stats: _stats!,
                        expanded: _showRawLog,
                        onToggle: () =>
                            setState(() => _showRawLog = !_showRawLog),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ── Header — current state at a glance ───────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final DeviceStats stats;
  const _HeaderCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = stats.batteryPercent;
    final mv = stats.batteryMv;
    final isCharging = stats.batteryCharging == true || pct == 255;
    final mins = stats.batteryMinutesRemaining;

    // Determine visual state
    final Color stateColor;
    final IconData stateIcon;
    final String stateLabel;
    if (pct == null) {
      stateColor = cs.onSurfaceVariant;
      stateIcon = Icons.battery_unknown;
      stateLabel = 'No data';
    } else if (isCharging) {
      stateColor = Colors.green;
      stateIcon = Icons.battery_charging_full;
      stateLabel = (mv != null && mv >= 4050) ? 'Fully charged' : 'Charging';
    } else if (pct <= 20) {
      stateColor = Colors.red;
      stateIcon = Icons.battery_alert;
      stateLabel = 'Low';
    } else if (pct <= 40) {
      stateColor = Colors.orange;
      stateIcon = Icons.battery_3_bar;
      stateLabel = 'Discharging';
    } else {
      stateColor = Colors.green;
      stateIcon = Icons.battery_full;
      stateLabel = 'Discharging';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXl),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(stateIcon, size: 64, color: stateColor),
                const SizedBox(width: AppConstants.spacingLg),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pct == null
                          ? '—'
                          : (isCharging && pct == 255 ? '—' : '$pct%'),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: stateColor,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stateLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (mv != null || mins != null) ...[
              const SizedBox(height: AppConstants.spacingLg),
              const Divider(height: 1),
              const SizedBox(height: AppConstants.spacingMd),
              Row(
                children: [
                  if (mv != null)
                    Expanded(
                      child: _StatTile(
                        label: 'Voltage',
                        value: '${(mv / 1000).toStringAsFixed(2)} V',
                      ),
                    ),
                  if (mv != null && mins != null && !isCharging)
                    Container(
                      width: 1,
                      height: 32,
                      color: cs.outlineVariant,
                    ),
                  if (mins != null && !isCharging)
                    Expanded(
                      child: _StatTile(
                        label: 'Remaining',
                        value: _formatMinutes(mins),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Range selector ───────────────────────────────────────────────────────

class _RangeSelector extends StatelessWidget {
  final _Range current;
  final ValueChanged<_Range> onChanged;
  const _RangeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Range>(
      segments: _Range.values
          .map((r) => ButtonSegment(value: r, label: Text(r.label)))
          .toList(),
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}

// ── Chart ────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final DeviceStats stats;
  final _Range range;
  const _ChartCard({required this.stats, required this.range});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filtered = _filterByRange(stats.batteryHistory, range);

    if (filtered.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingXl),
          child: Column(
            children: [
              Icon(Icons.timeline_rounded,
                  size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: AppConstants.spacingMd),
              Text(
                'Not enough history yet',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'The chart needs at least 2 data points in the selected range.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final earliest = filtered.first.timestamp;
    // Primary line: all samples (percent over time).
    final allSpots = filtered.map((e) {
      final mins = e.timestamp.difference(earliest).inMinutes.toDouble();
      return FlSpot(mins, e.percent.toDouble());
    }).toList();
    // Secondary markers: charging samples only — drawn as colored dots on top.
    final chargingSpots = <FlSpot>[];
    for (var i = 0; i < filtered.length; i++) {
      if (filtered[i].charging) {
        chargingSpots.add(allSpots[i]);
      }
    }

    final maxX = allSpots.last.x;
    if (maxX <= 0) return const SizedBox.shrink();

    final latestPct = filtered.last.percent;
    final latestCharging = filtered.last.charging;
    final lineColor = latestCharging
        ? Colors.blue
        : latestPct <= 20
            ? Colors.red
            : latestPct <= 40
                ? Colors.orange
                : Colors.green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              minX: 0,
              maxX: maxX,
              gridData: FlGridData(
                show: true,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 0.5,
                ),
                drawVerticalLine: false,
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 25,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: _bottomInterval(maxX),
                    getTitlesWidget: (value, meta) {
                      return Text(
                        _formatXLabel(value, maxX),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                // Main trajectory
                LineChartBarData(
                  spots: allSpots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: lineColor,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: lineColor.withValues(alpha: 0.12),
                  ),
                ),
                // Charging-point overlay: draw the same points again as just
                // dots in blue so charge periods read as "blue dots hiking
                // upward" — no separate segment math needed.
                if (chargingSpots.isNotEmpty)
                  LineChartBarData(
                    spots: chargingSpots,
                    color: Colors.transparent,
                    barWidth: 0,
                    isStrokeCapRound: false,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, a, b, c) => FlDotCirclePainter(
                        radius: 2.5,
                        color: Colors.blue,
                        strokeWidth: 0,
                      ),
                    ),
                  ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => cs.surface,
                  tooltipBorder: BorderSide(color: cs.outlineVariant),
                  getTooltipItems: (touched) {
                    return touched.map((ts) {
                      // ts.x is minutes from earliest.
                      final ts0 = earliest
                          .add(Duration(minutes: ts.x.toInt()));
                      final timeStr =
                          '${ts0.hour.toString().padLeft(2, '0')}:${ts0.minute.toString().padLeft(2, '0')}';
                      return LineTooltipItem(
                        '${ts.y.toInt()}%\n$timeStr',
                        theme.textTheme.bodySmall!.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _bottomInterval(double maxX) {
    if (maxX <= 60) return 15;
    if (maxX <= 180) return 30;
    if (maxX <= 720) return 120;
    return 360;
  }

  static String _formatXLabel(double minutes, double maxX) {
    if (maxX > 120) {
      final h = (minutes / 60);
      return '${h.toStringAsFixed(0)}h';
    }
    return '${minutes.toInt()}m';
  }
}

// ── Metrics ──────────────────────────────────────────────────────────────

class _MetricsCard extends StatelessWidget {
  final DeviceStats stats;
  final _Range range;
  const _MetricsCard({required this.stats, required this.range});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = _filterByRange(stats.batteryHistory, range);

    if (filtered.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          child: Center(
            child: Text(
              'No samples in range',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // Min / Max %
    int minPct = 100, maxPct = 0;
    int minMv = 9999, maxMv = 0;
    for (final e in filtered) {
      if (e.percent < minPct) minPct = e.percent;
      if (e.percent > maxPct) maxPct = e.percent;
      if (e.mv > 0) {
        if (e.mv < minMv) minMv = e.mv;
        if (e.mv > maxMv) maxMv = e.mv;
      }
    }

    // Charge cycles — count contiguous charging runs.
    int cycles = 0;
    bool wasCharging = false;
    for (final e in filtered) {
      if (e.charging && !wasCharging) cycles++;
      wasCharging = e.charging;
    }

    // Average discharge rate — only over non-charging stretches.
    final dischargeRate = _avgDischargePercentPerHour(filtered);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppConstants.spacingMd),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppConstants.spacingMd,
              mainAxisSpacing: AppConstants.spacingSm,
              childAspectRatio: 3.2,
              children: [
                _MetricTile(
                  label: 'Range',
                  value: '$minPct% – $maxPct%',
                  icon: Icons.show_chart_rounded,
                ),
                _MetricTile(
                  label: 'Voltage',
                  value: minMv < 9999
                      ? '${(minMv / 1000).toStringAsFixed(2)}–${(maxMv / 1000).toStringAsFixed(2)}V'
                      : '—',
                  icon: Icons.bolt_rounded,
                ),
                _MetricTile(
                  label: 'Charge cycles',
                  value: '$cycles',
                  icon: Icons.power_rounded,
                ),
                _MetricTile(
                  label: 'Discharge',
                  value: dischargeRate != null
                      ? '${dischargeRate.toStringAsFixed(1)}%/h'
                      : '—',
                  icon: Icons.trending_down_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static double? _avgDischargePercentPerHour(List<BatteryHistoryEntry> h) {
    if (h.length < 2) return null;
    int totalDrop = 0;
    int totalMinutes = 0;
    for (var i = 1; i < h.length; i++) {
      final prev = h[i - 1];
      final cur = h[i];
      if (prev.charging || cur.charging) continue;
      final drop = prev.percent - cur.percent;
      if (drop <= 0) continue; // ignore flat or upticks
      final dt = cur.timestamp.difference(prev.timestamp).inMinutes;
      if (dt <= 0) continue;
      totalDrop += drop;
      totalMinutes += dt;
    }
    if (totalMinutes == 0) return null;
    return totalDrop / (totalMinutes / 60.0);
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = theme.extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
        vertical: AppConstants.spacingSm,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ac.info),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Raw log ──────────────────────────────────────────────────────────────

class _RawLogCard extends StatelessWidget {
  final DeviceStats stats;
  final bool expanded;
  final VoidCallback onToggle;
  const _RawLogCard({
    required this.stats,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = stats.batteryHistory.reversed.toList(); // newest first

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Row(
                children: [
                  Icon(Icons.list_rounded, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppConstants.spacingSm),
                  Expanded(
                    child: Text(
                      'Raw history (${entries.length})',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppConstants.spacingLg),
                      child: Text(
                        'No entries recorded yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (ctx, i) => Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        final t = e.timestamp.toLocal();
                        final timeStr =
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
                        final dateStr =
                            '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            e.charging
                                ? Icons.bolt_rounded
                                : Icons.battery_std_rounded,
                            size: 18,
                            color: e.charging ? Colors.blue : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            '${e.percent}% · ${(e.mv / 1000).toStringAsFixed(2)}V',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: Text(
                            '$dateStr $timeStr',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

List<BatteryHistoryEntry> _filterByRange(
  List<BatteryHistoryEntry> history,
  _Range range,
) {
  final d = range.duration;
  if (d == null) return history;
  final cutoff = DateTime.now().subtract(d);
  return history.where((e) => e.timestamp.isAfter(cutoff)).toList();
}

String _formatMinutes(int mins) {
  if (mins < 0) return '—';
  if (mins >= 60) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
  return '${mins}m';
}
