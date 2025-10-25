import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // --- NEW: Import fl_chart ---
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
// FIX: Added missing import for data models.
import './models.dart';
import './services.dart';

// Fully responsive now
class ProgressPieChart extends StatelessWidget {
  final int completed;
  final int total;
  const ProgressPieChart(
      {super.key, required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final double percentage = total == 0 ? 0 : completed / total;

    // Use LayoutBuilder to get parent constraints
    return LayoutBuilder(builder: (context, constraints) {
      // Calculate sizes based on the smallest dimension of the parent
      final double chartSize = constraints.maxWidth < constraints.maxHeight
          ? constraints.maxWidth
          : constraints.maxHeight;

      // Calculate dynamic radius and font size
      final double radius = chartSize * 0.35; // 35% of the available size
      final double centerSpaceRadius = chartSize * 0.25; // 25%
      final double titleFontSize = chartSize * 0.1; // 10%

      return Container(
        width: chartSize,
        height: chartSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        child: PieChart(
          PieChartData(
            sections: [
              PieChartSectionData(
                  color: Colors.green.shade400,
                  value: percentage * 100,
                  title: '${(percentage * 100).toStringAsFixed(0)}%',
                  radius: radius,
                  titleStyle: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              PieChartSectionData(
                color: Colors.grey.shade200,
                value: (1 - percentage) * 100,
                title: '',
                radius: radius,
              ),
            ],
            centerSpaceRadius: centerSpaceRadius,
            sectionsSpace: 2,
          ),
        ),
      );
    });
  }
}

class ReportsPage extends StatefulWidget {
  // --- NEW: Added activeGoal ---
  final Goal? activeGoal;
  const ReportsPage({super.key, this.activeGoal});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
            Tab(text: 'Yearly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ReportView(
            title: 'Weekly Report',
            reportFuture: firestoreService.getWeeklyReport(),
            // --- NEW: Pass activeGoal to weekly report ---
            activeGoal: widget.activeGoal,
          ),
          ReportView(
            title: 'Monthly Report',
            reportFuture: firestoreService.getMonthlyReport(),
          ),
          ReportView(
            title: 'Yearly Report',
            reportFuture: firestoreService.getYearlyReport(),
            isYearly: true,
          ),
        ],
      ),
    );
  }
}

class ReportView extends StatelessWidget {
  final String title;
  final Future<Map<String, dynamic>> reportFuture;
  final bool isYearly;
  // --- NEW: Added activeGoal ---
  final Goal? activeGoal;

  const ReportView({
    super.key,
    required this.title,
    required this.reportFuture,
    this.isYearly = false,
    this.activeGoal, // --- NEW ---
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: reportFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
              child: Text('No data available for this period.'));
        }

        final reportData = snapshot.data!;
        final currentPeriod =
            reportData['currentPeriod'] as Map<String, dynamic>;
        final previousPeriod =
            reportData['previousPeriod'] as Map<String, dynamic>;
        final summary = reportData['summary'] as String?;
        final checkinCounts =
            currentPeriod['checkinCounts'] as Map<TaskCheckinStatus, int>;
        final archivedGoals = reportData['archivedGoals'] as List<Goal>?;

        final Duration currentDuration = currentPeriod['timeSpent'];
        final int currentTasks = currentPeriod['tasksCompleted'];
        final Duration previousDuration = previousPeriod['timeSpent'];
        final int previousTasks = previousPeriod['tasksCompleted'];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- NEW: Display Pie Chart if activeGoal is provided ---
            if (activeGoal != null && activeGoal!.totalTasks > 0) ...[
              const Text(
                "Overall Goal Progress",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              AspectRatio(
                aspectRatio: 1.5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48.0, vertical: 16.0),
                  child: ProgressPieChart(
                    completed: activeGoal!.completedTasks,
                    total: activeGoal!.totalTasks,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            // --- End of new section ---

            if (summary != null && summary.isNotEmpty) ...[
              const Text(
                "Your Monthly Summary",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    summary,
                    style: const TextStyle(
                        fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            const Text(
              "Performance This Period",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ReportCard(
              timeSpent: _formatDuration(currentDuration),
              tasksCompleted: currentTasks.toString(),
              comparisonTime:
                  currentDuration.inSeconds - previousDuration.inSeconds,
              comparisonTasks: currentTasks - previousTasks,
            ),
            const SizedBox(height: 24),
            // --- NEW: Check-in Summary Card ---
            const Text(
              "Check-in Summary",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            CheckinSummaryCard(checkinCounts: checkinCounts),

            if (isYearly &&
                archivedGoals != null &&
                archivedGoals.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                "Archived Goals This Year",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...archivedGoals.map((goal) => ArchivedGoalCard(goal: goal)),
            ]
          ],
        );
      },
    );
  }
}

// --- NEW: Card to display check-in summary ---
class CheckinSummaryCard extends StatelessWidget {
  final Map<TaskCheckinStatus, int> checkinCounts;
  const CheckinSummaryCard({super.key, required this.checkinCounts});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CheckinRow(
                status: TaskCheckinStatus.done,
                count: checkinCounts[TaskCheckinStatus.done] ?? 0),
            const Divider(),
            CheckinRow(
                status: TaskCheckinStatus.doing,
                count: checkinCounts[TaskCheckinStatus.doing] ?? 0),
            const Divider(),
            CheckinRow(
                status: TaskCheckinStatus.willDo,
                count: checkinCounts[TaskCheckinStatus.willDo] ?? 0),
            const Divider(),
            CheckinRow(
                status: TaskCheckinStatus.wontDo,
                count: checkinCounts[TaskCheckinStatus.wontDo] ?? 0),
          ],
        ),
      ),
    );
  }
}

// --- NEW: Row for the check-in summary card ---
class CheckinRow extends StatelessWidget {
  final TaskCheckinStatus status;
  final int count;
  const CheckinRow({super.key, required this.status, required this.count});

  @override
  Widget build(BuildContext context) {
    final Map<TaskCheckinStatus, dynamic> details = {
      TaskCheckinStatus.done: {
        'text': 'Done',
        'icon': Icons.check_circle_outline,
        'color': Colors.green
      },
      TaskCheckinStatus.doing: {
        'text': 'Doing',
        'icon': Icons.directions_run,
        'color': Colors.blue
      },
      TaskCheckinStatus.willDo: {
        'text': 'Will Do',
        'icon': Icons.schedule,
        'color': Colors.orange
      },
      TaskCheckinStatus.wontDo: {
        'text': 'Won\'t Do',
        'icon': Icons.cancel_outlined,
        'color': Colors.red
      },
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(details[status]['icon'], color: details[status]['color']),
          const SizedBox(width: 16),
          Text(details[status]['text'], style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(count.toString(),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// --- NEW: Card to display an archived goal ---
class ArchivedGoalCard extends StatelessWidget {
  final Goal goal;
  const ArchivedGoalCard({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    final isAchieved = goal.status == GoalStatus.achieved;
    return Card(
      color: isAchieved ? Colors.green.shade50 : Colors.red.shade50,
      child: ListTile(
        leading: Icon(
          isAchieved ? Icons.emoji_events_rounded : Icons.flag_rounded,
          color: isAchieved ? Colors.green.shade700 : Colors.red.shade700,
        ),
        title: Text(goal.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(isAchieved ? 'Achieved!' : 'Given Up'),
      ),
    );
  }
}

class ReportCard extends StatelessWidget {
  final String timeSpent;
  final String tasksCompleted;
  final int comparisonTime; // in seconds
  final int comparisonTasks;

  const ReportCard({
    super.key,
    required this.timeSpent,
    required this.tasksCompleted,
    required this.comparisonTime,
    required this.comparisonTasks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ReportRow(
              icon: Icons.timer_outlined,
              label: 'Time Spent',
              value: timeSpent,
              comparisonValue: comparisonTime,
              isTime: true,
            ),
            const Divider(),
            ReportRow(
              icon: Icons.check_circle_outline,
              label: 'Tasks Completed',
              value: tasksCompleted,
              comparisonValue: comparisonTasks,
            ),
          ],
        ),
      ),
    );
  }
}

class ReportRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final int comparisonValue;
  final bool isTime;

  const ReportRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.comparisonValue,
    this.isTime = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = comparisonValue >= 0 ? Colors.green : Colors.red;
    final IconData trendIcon =
        comparisonValue >= 0 ? Icons.trending_up : Icons.trending_down;

    String comparisonText;
    if (isTime) {
      final duration = Duration(seconds: comparisonValue.abs());
      comparisonText =
          "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    } else {
      comparisonText = comparisonValue.abs().toString();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Icon(trendIcon, color: color, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    comparisonText,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }
}
