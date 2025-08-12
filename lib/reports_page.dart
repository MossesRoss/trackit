import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import './models.dart';
import './services.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

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
          ),
          ReportView(
            title: 'Monthly Report',
            reportFuture: firestoreService.getMonthlyReport(),
          ),
          ReportView(
            title: 'Yearly Report',
            reportFuture: firestoreService.getYearlyReport(),
          ),
        ],
      ),
    );
  }
}

class ReportView extends StatelessWidget {
  final String title;
  final Future<Map<String, dynamic>> reportFuture;

  const ReportView({
    super.key,
    required this.title,
    required this.reportFuture,
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
          return const Center(child: Text('No data available for this period.'));
        }

        final reportData = snapshot.data!;
        final currentPeriod = reportData['currentPeriod'] as Map<String, dynamic>;
        final previousPeriod = reportData['previousPeriod'] as Map<String, dynamic>;
        final summary = reportData['summary'] as String?; // FIX: Renamed

        final Duration currentDuration = currentPeriod['timeSpent'];
        final int currentTasks = currentPeriod['tasksCompleted'];
        final Duration previousDuration = previousPeriod['timeSpent'];
        final int previousTasks = previousPeriod['tasksCompleted'];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (summary != null && summary.isNotEmpty) ...[
              const Text(
                "Your Monthly Summary", // FIX: Removed "AI-Powered"
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    summary,
                    style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
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
              comparisonTime: currentDuration.inSeconds - previousDuration.inSeconds,
              comparisonTasks: currentTasks - previousTasks,
            ),
          ],
        );
      },
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
      comparisonText = "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
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

