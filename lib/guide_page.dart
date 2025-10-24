import 'package:flutter/material.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("How to Use (Guide)")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          HelpTile(
            icon: Icons.track_changes_rounded,
            title: "The Power of a Clear Goal",
            content:
                "Goals give you direction and focus. They turn your dreams into a destination. When you know where you're going, you can start planning the journey. Think of it as the difference between wandering aimlessly and following a map to a hidden treasure. Every step you take is a step closer to success.",
          ),
          HelpTile(
            icon: Icons.rule_rounded,
            title: "Set Goals the SMART Way",
            content:
                'To make your goals more powerful, make them SMART:\n\nSpecific: Instead of "get fit," try "run a 5k race."\nMeasurable: Track your progress. "Run 3 times a week."\nAchievable: Start with a goal you can realistically meet.\nRelevant: Does this goal matter to you right now?\nTime-bound: Set a deadline. "Run a 5k in 3 months."',
          ),
          HelpTile(
            icon: Icons.splitscreen_rounded,
            title: "Break It Down, Build It Up",
            content:
                "Big goals can feel overwhelming. The secret is to break them into smaller, manageable tasks. Want to write a book? Start with one chapter, then one page, then one paragraph. Our app lets you create milestones and tasks for your main goal. Ticking off these small wins will keep you motivated and build momentum.",
          ),
          HelpTile(
            icon: Icons.show_chart_rounded,
            title: "Track Your Progress, Stay Motivated",
            content:
                "Seeing how far you've come is a powerful motivator. Use our app's reporting features to log your efforts and celebrate your milestones. Whether it's a chart showing your progress or a simple checklist, visual feedback makes your hard work feel real and rewarding. Don't forget to look back at your journey and see your success!",
          ),
          HelpTile(
            icon: Icons.alt_route_rounded,
            title: "Stay Flexible, Adjust as You Go",
            content:
                "Life happens! It's okay if you need to adjust your plan. A goal isn't set in stone. It's a guide, not a rule. If you miss a day or find a better approach, use our app to update your milestones or timeline. The key is to stay engaged with your goal and keep moving forward, no matter the pace.",
          ),
          HelpTile(
            icon: Icons.celebration_rounded,
            title: "Celebrate Every Victory!",
            content:
                "Don't wait until the very end to celebrate. Every step forward is a victory. Did you complete a task? Did you stick to your schedule for a week? Acknowledge your effort! Use our app's features to mark your achievements. Celebrating small wins makes the journey enjoyable and fuels your motivation for the long run.",
          ),
        ],
      ),
    );
  }
}

// This widget is used by GuidePage
class HelpTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  const HelpTile(
      {super.key,
      required this.icon,
      required this.title,
      required this.content});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
    );
  }
}
