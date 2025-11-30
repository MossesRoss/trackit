/*
 * @author Mosses
 * @version 1.5.0
 * --- CHANGELOG ---
 * v1.5.0:
 * - [FEAT] Reports page now checks for an active goal before building.
 * If no active goal is found, it displays "Set goal first."
 * - [FIX] Cleaned up redundant "no active goal" check in `OverallReportView`
 * as it is now handled by the parent `ReportsPage`.
 * - [FIX] `ArchivedGoalCard` in Yearly tab now uses theme-aware colors
 * (`primaryContainer`/`errorContainer`) to fix dark mode visibility.
 * v1.4.0:
 * - [FIX] Changed `OverallReportView` to use a `StreamBuilder` on
 * `firestoreService.getGoalsStream()` instead of relying on a
 * prop-drilled `activeGoal`. This fixes a bug where the 'Overall'
 * tab would show stale data after a notification action.
 * - [FEAT] Removed `activeGoal` parameter from `ReportsPage` as it's
 * no longer needed.
 */
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // Import fl_chart
// import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
// FIX: Added missing import for data models.
import './models.dart';
import './services.dart';
import './widgets/sexy_chart.dart';

// --- PERFORMANCE FIX: Removed LayoutBuilder ---
class ProgressPieChart extends StatelessWidget {
  final int completed;
  final int total;
  const ProgressPieChart(
      {super.key, required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final double percentage = total == 0 ? 0 : completed / total;

    // --- PERFORMANCE FIX: Use fixed sizes ---
    const double chartSize = 220.0;
    const double radius = chartSize * 0.35;
    const double centerSpaceRadius = chartSize * 0.25;
    const double titleFontSize = chartSize * 0.1;

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
                titleStyle: const TextStyle(
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
  }
}

class ReportsPage extends StatefulWidget {
  // --- FIX: Removed activeGoal property ---
  // final Goal? activeGoal;
  // const ReportsPage({super.key, this.activeGoal});
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- FIX: Define streams as state variables ---
  late Stream<Map<String, dynamic>> _weeklyReportStream;
  late Stream<Map<String, dynamic>> _monthlyReportStream;
  late Stream<Map<String, dynamic>> _yearlyReportStream;
  // --- FIX: Add goals stream to check for active goal ---
  late Stream<List<Goal>> _goalsStream;

  @override
  void initState() {
    super.initState();
    // --- FIX: Add new tab ---
    _tabController = TabController(length: 4, vsync: this);

    // --- FIX: Get service and initialize streams ONCE ---
    // We use listen: false because this should only run once
    // and not cause initState to re-run if the provider changes.
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);
    // --- FIX: Initialize goals stream ---
    _goalsStream = firestoreService.getGoalsStream();
    _weeklyReportStream = firestoreService.getWeeklyReport();
    _monthlyReportStream = firestoreService.getMonthlyReport();
    _yearlyReportStream = firestoreService.getYearlyReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This call is no longer needed here:
    // final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            // --- FIX: Add new 'Overall' tab ---
            Tab(text: 'Overall'),
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
            Tab(text: 'Yearly'),
          ],
        ),
      ),
      // --- FIX: Wrap body in StreamBuilder to check for active goal ---
      body: StreamBuilder<List<Goal>>(
        stream: _goalsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            // This case also catches errors, though snapshot.hasError is better
            return const Center(child: Text("Loading..."));
          }

          final allGoals = snapshot.data ?? [];
          Goal? activeGoal;
          try {
            activeGoal =
                allGoals.firstWhere((g) => g.status == GoalStatus.active);
          } catch (e) {
            activeGoal = null;
          }

          // If no active goal, show message
          if (activeGoal == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Set goal first", // <-- User's requested text
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                ),
              ),
            );
          }

          // If active goal exists, show the TabBarView
          return TabBarView(
            controller: _tabController,
            children: [
              // --- FIX: Remove activeGoal property ---
              const OverallReportView(),
              // Was: OverallReportView(activeGoal: widget.activeGoal),

              // --- FIX: Pass the persistent streams from state ---
              ReportView(
                title: 'Weekly Report',
                reportStream: _weeklyReportStream,
              ),
              ReportView(
                title: 'Monthly Report',
                reportStream: _monthlyReportStream,
              ),
              ReportView(
                title: 'Yearly Report',
                reportStream: _yearlyReportStream,
                isYearly: true,
              ),
            ],
          );
        },
      ),
      // --- End of fix ---
    );
  }
}

class OverallReportView extends StatelessWidget {
  const OverallReportView({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return StreamBuilder<List<Goal>>(
        stream: firestoreService.getGoalsStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Loading..."));
          }

          final allGoals = snapshot.data!;
          Goal? activeGoal;
          try {
            activeGoal =
                allGoals.firstWhere((g) => g.status == GoalStatus.active);
          } catch (e) {
            activeGoal = null;
          }

          // --- FIX: Removed redundant "No active goal" message ---
          // This is now handled by the parent ReportsPage
          if (activeGoal == null) {
            // This should technically not be reached if parent is fixed
            return const Center(child: Text("Loading..."));
          }

          if (activeGoal.totalTasks == 0) {
            // --- End of fix ---
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  // "No active goal to display. Set a goal and complete tasks to see your progress here.",
                  // --- FIX: Changed message to be specific to this case ---
                  "No tasks added to your active goal yet.",
                  // --- End of fix ---
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // --- FIX: WRAP THE WIDGET IN A SingleChildScrollView ---
          return SingleChildScrollView(
            child: Center(
              // --- STYLE: Add padding and change alignment ---
              child: Padding(
                // Added top and bottom padding for scrolling room
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start, // <-- FIX
                  children: [
                    // --- STYLE: Remove redundant title ---
                    // const Text(
                    //   "Overall Goal Progress",
                    //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    // ),
                    // --- STYLE: Remove extra space ---
                    // const SizedBox(height: 24),
                    SexyProgressChart(
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }
}

class ReportView extends StatelessWidget {
  final String title;
  // --- FIX: Change from Future to Stream ---
  final Stream<Map<String, dynamic>> reportStream;
  final bool isYearly;

  const ReportView({
    super.key,
    required this.title,
    // --- FIX: Update constructor ---
    required this.reportStream,
    this.isYearly = false,
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
    // --- FIX: Change to StreamBuilder ---
    return StreamBuilder<Map<String, dynamic>>(
      // --- FIX: Use the new stream ---
      stream: reportStream,
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
        // --- FIX: Ensure checkinCounts is not null ---
        final checkinCounts =
            (currentPeriod['checkinCounts'] as Map<TaskCheckinStatus, int>?) ??
                {};
        final archivedGoals = reportData['archivedGoals'] as List<Goal>?;

        final Duration currentDuration =
            currentPeriod['timeSpent'] ?? Duration.zero;
        final int currentTasks = currentPeriod['tasksCompleted'] ?? 0;
        final Duration previousDuration =
            previousPeriod['timeSpent'] ?? Duration.zero;
        final int previousTasks = previousPeriod['tasksCompleted'] ?? 0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- FIX: Removed Pie Chart from here ---

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

    // --- FIX: Use theme-aware colors for dark mode ---
    final Color cardColor = isAchieved
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.errorContainer;
    final Color contentColor = isAchieved
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onErrorContainer;
    // --- End of fix ---

    return Card(
      color: cardColor, // <-- FIX
      child: ListTile(
        leading: Icon(
          isAchieved ? Icons.emoji_events_rounded : Icons.flag_rounded,
          color: contentColor, // <-- FIX
        ),
        title: Text(goal.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: contentColor, // <-- FIX
            )),
        subtitle: Text(
          isAchieved ? 'Achieved!' : 'Given Up',
          style: TextStyle(color: contentColor.withAlpha(204)), // <-- FIX
        ),
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
