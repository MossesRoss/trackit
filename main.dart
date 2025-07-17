import 'package:flutter/material.dart';
import 'dart:math';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Milestone Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainPage(),
    );
  }
}

class Milestone {
  String title;
  DateTime deadline;
  List<String> checkpoints;
  List<bool> completed;

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
  }) : completed = List<bool>.filled(checkpoints.length, false);

  double get progress =>
      completed.where((c) => c).length / max(1, checkpoints.length);
}

class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  String? _target;
  final TextEditingController _goalController = TextEditingController();
  final List<Milestone> _milestones = [];

  void _addMainGoal(String goal) {
    if (goal.trim().isEmpty) return;
    setState(() {
      _target = goal.trim();
      _goalController.clear();
    });
  }

  void _addMilestone() {
    showDialog(
      context: context,
      builder: (context) {
        final titleController = TextEditingController();
        final deadlineController = TextEditingController();
        final checkpointsController = TextEditingController();
        return AlertDialog(
          title: Text('New Milestone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: InputDecoration(hintText: 'Milestone Title')),
              TextField(controller: deadlineController, decoration: InputDecoration(hintText: 'Deadline (YYYY-MM-DD)')),
              TextField(controller: checkpointsController, decoration: InputDecoration(hintText: 'Checkpoints (comma separated)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(
              onPressed: () {
                final title = titleController.text;
                final deadline = DateTime.tryParse(deadlineController.text);
                final checkpoints = checkpointsController.text.split(',').map((e) => e.trim()).toList();
                if (title.isNotEmpty && deadline != null && checkpoints.isNotEmpty) {
                  setState(() {
                    _milestones.add(Milestone(title: title, deadline: deadline, checkpoints: checkpoints));
                  });
                  Navigator.pop(context);
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _toggleCheckpoint(Milestone milestone, int index) {
    setState(() {
      milestone.completed[index] = !milestone.completed[index];
    });
  }

  Widget _buildHomePage() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_target == null) ...[
            TextField(
              controller: _goalController,
              textAlign: TextAlign.center,
              decoration: InputDecoration(hintText: 'Enter your main goal'),
              onSubmitted: _addMainGoal,
            ),
            SizedBox(height: 10),
            ElevatedButton(onPressed: () => _addMainGoal(_goalController.text), child: Text('Set Goal')),
          ] else ...[
            Text('Your Main Goal:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(_target!, style: TextStyle(fontSize: 24)),
          ],
        ],
      ),
    );
  }

  Widget _buildMilestonesPage() {
    Milestone? closest = _milestones.isNotEmpty ? (_milestones..sort((a, b) => a.deadline.compareTo(b.deadline))).first : null;

    return Column(
      children: [
        if (_target != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('🎯 $_target', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        if (closest != null) ...[
          Text('Closest Milestone:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(closest.title, style: TextStyle(fontSize: 16)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: LinearProgressIndicator(value: closest.progress),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("You haven't set any milestones yet."),
          ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: _milestones.length,
            itemBuilder: (context, index) {
              final milestone = _milestones[index];
              return Card(
                margin: EdgeInsets.all(8),
                child: ExpansionTile(
                  title: Text(milestone.title),
                  subtitle: Text('Deadline: ${milestone.deadline.toLocal().toString().split(' ')[0]}'),
                  children: List.generate(milestone.checkpoints.length, (i) {
                    return CheckboxListTile(
                      value: milestone.completed[i],
                      title: Text(milestone.checkpoints[i]),
                      onChanged: (_) => _toggleCheckpoint(milestone, i),
                    );
                  }),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: _addMilestone,
            icon: Icon(Icons.add),
            label: Text('Add Milestone'),
          ),
        )
      ],
    );
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: Icon(Icons.notifications), title: Text('Notifications'), onTap: () {}),
          ListTile(leading: Icon(Icons.color_lens), title: Text('Theme'), onTap: () {}),
          ListTile(leading: Icon(Icons.info), title: Text('About'), onTap: () {}),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> _pages = [_buildHomePage(), _buildMilestonesPage()];
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Home' : 'Milestones'),
        centerTitle: true,
        actions: [IconButton(icon: Icon(Icons.settings), onPressed: _openSettings)],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'Milestones'),
        ],
      ),
    );
  }
}
