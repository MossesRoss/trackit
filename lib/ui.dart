import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import './models.dart';
import './services.dart';
import './reports_page.dart';
import './notification_service.dart'; // Import the new service
import './guide_page.dart'; // --- NEW: Import the new guide page ---

class HomePage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(String) onSetGoal;
  final Function(String, Duration) onTimeAdd;
  final VoidCallback onGiveUp;

  const HomePage(
      {super.key,
      this.activeGoal,
      required this.onSetGoal,
      required this.onTimeAdd,
      required this.onGiveUp});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _suggestion = "";
  bool _isLoading = true; // --- MODIFIED: Start as true ---

  Milestone? get _nextMilestone {
    if (widget.activeGoal == null) return null;
    for (final milestone in widget.activeGoal!.milestones) {
      if (!milestone.isCompleted) {
        return milestone;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fetchSuggestion();
  }

  Future<void> _fetchSuggestion() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String? currentMilestoneId = _nextMilestone?.id;

    // --- NEW: Check cache first ---
    final String? cachedDate = prefs.getString('suggestion_cache_date');
    final String? cachedMilestoneId =
        prefs.getString('suggestion_cache_milestone_id');
    final String? cachedSuggestion =
        prefs.getString('suggestion_cache_content');

    if (cachedDate == currentDate &&
        cachedMilestoneId == currentMilestoneId &&
        cachedSuggestion != null) {
      if (mounted) {
        setState(() {
          _suggestion = cachedSuggestion;
          _isLoading = false;
        });
      }
      return; // Use cached data
    }

    // --- No valid cache, fetch new suggestion ---
    final result = await SuggestionService.getSuggestion(
        widget.activeGoal, _nextMilestone);

    if (mounted) {
      String textToShow;
      if (result.suggestion != null) {
        textToShow = result.suggestion!;
        // Save to cache
        await prefs.setString('suggestion_cache_date', currentDate);
        await prefs.setString(
            'suggestion_cache_milestone_id', currentMilestoneId ?? '');
        await prefs.setString('suggestion_cache_content', textToShow);
      } else {
        // --- NEW: Handle errors and get fallback ---
        if (result.error == "NO_API_KEY") {
          textToShow =
              "Please set your Gemini API key in Settings to get AI suggestions.";
        } else {
          // API error or network error, get a quote
          textToShow = await QuoteService.getQuote();
        }
      }

      setState(() {
        _suggestion = textToShow;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- MODIFIED: AppBar title is now back to the goal title ---
      appBar: AppBar(
        title: Text(widget.activeGoal?.title ?? 'Track It'),
        actions: [
          if (widget.activeGoal != null)
            IconButton(
              icon: const Icon(Icons.outlined_flag_rounded),
              tooltip: 'Give Up Goal',
              onPressed: widget.onGiveUp,
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: widget.activeGoal == null
              ? GoalSetterCard(onSetGoal: widget.onSetGoal)
              // --- MODIFIED: New UI for active goal ---
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- REMOVED: Goal title Text widget removed from body ---
                    const SizedBox(height: 40),
                    if (_nextMilestone != null)
                      GoalTimerCircle(
                        // Pass key to update when goal time changes
                        key: ValueKey(
                            widget.activeGoal!.totalTimeSpent.inSeconds),
                        goal: widget.activeGoal!,
                        nextMilestone: _nextMilestone!,
                        onTimeAdd: widget.onTimeAdd,
                      )
                    else
                      const Center(
                          child: Text("All milestones complete! 🎉",
                              style: TextStyle(fontSize: 18))),
                    const SizedBox(height: 40),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Text(
                            _suggestion,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color
                                    ?.withOpacity(0.8)),
                          ),
                    const Spacer(),
                  ],
                ),
        ),
      ),
    );
  }
}

// --- NEW: Widget for the animated timer circle ---
class GoalTimerCircle extends StatefulWidget {
  final Goal goal;
  final Milestone nextMilestone;
  final Function(String, Duration) onTimeAdd;

  const GoalTimerCircle({
    super.key,
    required this.goal,
    required this.nextMilestone,
    required this.onTimeAdd,
  });

  @override
  State<GoalTimerCircle> createState() => _GoalTimerCircleState();
}

class _GoalTimerCircleState extends State<GoalTimerCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  // Timer state
  Timer? _timer;
  int _secondsElapsed = 0;
  bool _isTimerRunning = false;

  // UI fade state
  bool _showTimer = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750), // Default start duration
    )..addListener(() {
        setState(() {});
      });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // --- MODIFIED: Check if timer is running to decide action ---
        if (_isTimerRunning) {
          // Animation complete, STOP the timer
          _stopTimer();
        } else {
          // Animation complete, START the timer
          _startTimer();
        }
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _timer?.cancel();
    // Ensure notification is cancelled if widget is disposed
    if (_isTimerRunning) {
      NotificationService().cancelFocusNotification();
    }
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _isTimerRunning = true;
      _showTimer = true; // Fade to timer
    });

    NotificationService().showFocusNotification(
      widget.nextMilestone.title,
      // Payload to reopen the app
      json.encode({'action': 'OPEN_HOME'}),
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    NotificationService().cancelFocusNotification();

    if (_secondsElapsed > 0) {
      widget.onTimeAdd(
          widget.nextMilestone.id, Duration(seconds: _secondsElapsed));
    }

    setState(() {
      _secondsElapsed = 0;
      _isTimerRunning = false;
      _showTimer = false; // Fade back to total hours
      _animationController.reset();
    });
  }

  // --- Long press gesture handlers ---
  void _onLongPressStart(LongPressStartDetails details) {
    // --- MODIFIED: Set duration based on timer state ---
    if (_isTimerRunning) {
      // Set shorter duration for STOP animation
      _animationController.duration = const Duration(milliseconds: 400);
    } else {
      // Set longer duration for START animation
      _animationController.duration = const Duration(milliseconds: 750);
    }
    _animationController.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_animationController.status != AnimationStatus.completed) {
      _animationController.reverse();
    }
  }

  // --- Tap handler ---
  void _onTap() {
    // --- MODIFIED: Only show a hint, do not stop timer ---
    if (_isTimerRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Hold the circle to stop the session."),
        duration: Duration(seconds: 2),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Hold the circle to start a focus session."),
        duration: Duration(seconds: 2),
      ));
    }
  }

  String _formatTotalHours(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours} Hours";
    }
    if (duration.inMinutes > 0) {
      return "${duration.inMinutes} Mins";
    }
    return "${duration.inSeconds} Secs";
  }

  String _formatRunningTime(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onTap: _onTap,
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Animation ring
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                value: _animationController.value,
                strokeWidth: 10,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            // Background circle
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.1),
              ),
            ),
            // AnimatedCrossFade for text
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              // Show timer text if _showTimer is true
              firstChild: Text(
                _formatRunningTime(_secondsElapsed),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  fontFamily: 'monospace',
                ),
              ),
              // Show total hours text if _showTimer is false
              secondChild: Text(
                _formatTotalHours(widget.goal.totalTimeSpent),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              crossFadeState: _showTimer
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
            ),
          ],
        ),
      ),
    );
  }
}

// --- MilestonesPage (Unchanged) ---
class MilestonesPage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(Milestone) onAddMilestone;
  final Function(Milestone, String) onToggleCheckpoint;
  final Function(String) onDeleteMilestone;
  final bool editMode;

  const MilestonesPage(
      {super.key,
      this.activeGoal,
      required this.onAddMilestone,
      required this.onToggleCheckpoint,
      required this.onDeleteMilestone,
      required this.editMode});

  @override
  State<MilestonesPage> createState() => MilestonesPageState();
}

class MilestonesPageState extends State<MilestonesPage> {
  void showAddMilestoneDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddMilestoneForm(
          onAdd: widget.onAddMilestone,
          goalTitle: widget.activeGoal?.title ?? "your goal",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Milestones'),
        actions: [
          if (widget.editMode && widget.activeGoal != null)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => showAddMilestoneDialog(context),
              tooltip: 'Add Milestone',
            ),
        ],
      ),
      body: widget.activeGoal == null
          ? const Center(child: Text("Set a main goal on the Home page first."))
          : widget.activeGoal!.milestones.isEmpty
              ? const Center(
                  child: Text("No milestones yet. Add one to start!"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: widget.activeGoal!.milestones.length,
                  itemBuilder: (context, index) {
                    final milestone = widget.activeGoal!.milestones[index];
                    return MilestoneNode(
                      key: ValueKey('${milestone.id}-${milestone.progress}'),
                      milestone: milestone,
                      isFirst: index == 0,
                      isLast: index == widget.activeGoal!.milestones.length - 1,
                      onToggleCheckpoint: widget.onToggleCheckpoint,
                      onDelete: () => widget.onDeleteMilestone(milestone.id),
                      editMode: widget.editMode,
                    );
                  },
                ),
    );
  }
}

// --- FIX: Rebuild the entire SettingsPage widget ---
class SettingsPage extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback toggleDarkMode;
  final bool editMode;
  final Function(bool) onEditModeChanged;
  final List<Goal> allGoals;

  const SettingsPage(
      {super.key,
      required this.isDarkMode,
      required this.toggleDarkMode,
      required this.editMode,
      required this.onEditModeChanged,
      required this.allGoals});

  // --- Dialog to set API Key ---
  void _showApiKeyDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final _apiKeyController =
        TextEditingController(text: prefs.getString('gemini_api_key'));

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Set Gemini API Key"),
          content: TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: "API Key"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                await prefs.setString(
                    'gemini_api_key', _apiKeyController.text.trim());
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("API Key saved!")));
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // --- _launchURL method ---
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    // --- Find the active goal to pass to ReportsPage ---
    Goal? activeGoal;
    try {
      activeGoal = allGoals.firstWhere((g) => g.status == GoalStatus.active);
    } catch (e) {
      activeGoal = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: isDarkMode,
            onChanged: (val) => toggleDarkMode(),
            secondary: const Icon(Icons.dark_mode_rounded),
          ),
          SwitchListTile(
            title: const Text('Edit Mode'),
            subtitle: const Text("Allows adding/deleting milestones"),
            value: editMode,
            onChanged: onEditModeChanged,
            secondary: const Icon(Icons.edit_rounded),
          ),
          // --- API Key Tile ---
          ListTile(
            leading: const Icon(Icons.api_rounded),
            title: const Text("Gemini API Key"),
            subtitle: const Text("Set your personal API key for AI features"),
            onTap: () => _showApiKeyDialog(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.assessment_rounded),
            title: const Text("Reports"),
            subtitle: const Text("View your weekly and monthly progress"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                // --- MODIFIED: Pass the activeGoal to ReportsPage ---
                builder: (_) => ReportsPage(activeGoal: activeGoal))),
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text("My Journey"),
            subtitle: const Text("View all your past and present goals"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MyJourneyPage(allGoals: allGoals))),
          ),
          ListTile(
              leading: const Icon(Icons.notifications_rounded),
              title: const Text("Notifications"),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        NotificationsSettingsPage(activeGoal: activeGoal)));
              }),
          // --- MODIFIED: "Help" is now "Guide" ---
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text("How to Use (Guide)"),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GuidePage())),
          ),
          // --- NEW: Technical Help section ---
          ExpansionTile(
            leading: const Icon(Icons.vpn_key_rounded),
            title: const Text("Technical Help"),
            subtitle: const Text("How to get your API key"),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
                        .copyWith(left: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "To use the AI suggestion features, you need a free Gemini API key from Google's AI Studio.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "1. Go to aistudio.google.com on a computer.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const Text(
                      "2. Sign in with your Google account.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const Text(
                      "3. Click 'Get API key' on the left menu.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const Text(
                      "4. Click 'Create API key in new project'.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const Text(
                      "5. Copy the long string of letters and numbers.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const Text(
                      "6. Come back here and paste it in the 'Gemini API Key' setting above.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          _launchURL("https://aistudio.google.com/"),
                      child: const Text("Open Google AI Studio"),
                    )
                  ],
                ),
              )
            ],
          ),
          ListTile(
            leading: const Icon(Icons.connect_without_contact_rounded),
            title: const Text("Get in Touch"),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GetInTouchPage())),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: Colors.red.shade400),
            title: const Text("Sign Out"),
            onTap: () {
              authService.signOut();
            },
          ),
        ],
      ),
    );
  }
}

// --- FIX: Add back the GetInTouchPage widget ---
class GetInTouchPage extends StatelessWidget {
  const GetInTouchPage({super.key});

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Get in Touch")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.email_rounded),
                title: const Text("Contact Us"),
                subtitle: const Text("For feedback or support"),
                onTap: () => _launchURL(
                    "mailto:pachamangacorp@gmail.com?subject=Feedback for Milestone App"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.favorite_rounded, color: Colors.red),
                title: const Text("Donate"),
                subtitle: const Text("Support the development"),
                onTap: () => _launchURL(
                    "https://drive.google.com/file/d/1b2s0u5msfpqn7finiw8Vx1ELgbWUrbW9/view?usp=sharing"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text("Contribute"),
                subtitle: const Text("Help improve the app on GitHub"),
                onTap: () => _launchURL(
                    "https://github.com/MossesRoss/trackit/edit/main/main.dart"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- GoalSetterCard (Unchanged) ---
class GoalSetterCard extends StatefulWidget {
  final Function(String) onSetGoal;
  final bool isNewGoal;
  const GoalSetterCard(
      {super.key, required this.onSetGoal, this.isNewGoal = false});

  @override
  State<GoalSetterCard> createState() => _GoalSetterCardState();
}

class _GoalSetterCardState extends State<GoalSetterCard> {
  final _controller = TextEditingController();

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSetGoal(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isNewGoal)
              const Text("Previous Goal Achieved!",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            const SizedBox(height: 8),
            Text(
                widget.isNewGoal
                    ? "What's your next big goal?"
                    : "What is your main goal?",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "e.g., Launch My App",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: const Text("Set New Goal"),
            ),
          ],
        ),
      ),
    );
  }
}

// --- MilestoneNode (FIXED) ---
class MilestoneNode extends StatelessWidget {
  final Milestone milestone;
  final bool isFirst;
  final bool isLast;
  final Function(Milestone, String) onToggleCheckpoint;
  final VoidCallback onDelete;
  final bool editMode;

  const MilestoneNode(
      {super.key,
      required this.milestone,
      required this.isFirst,
      required this.isLast,
      required this.onToggleCheckpoint,
      required this.onDelete,
      required this.editMode});

  String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) return "${duration.inSeconds}s";
    if (duration.inHours == 0) {
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    }
    return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
  }

  Future<void> _confirmToggle(
      BuildContext context, Checkpoint checkpoint) async {
    if (editMode) {
      onToggleCheckpoint(milestone, checkpoint.id);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(milestone.completedCheckpointIds.contains(checkpoint.id)
            ? "Mark as Incomplete?"
            : "Mark as Complete?"),
        content: const Text(
            "Are you sure you want to change the status of this task?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Confirm")),
        ],
      ),
    );
    if (confirm == true) {
      onToggleCheckpoint(milestone, checkpoint.id);
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Milestone?'),
        content: Text(
            "Are you sure you want to delete '${milestone.title}'? This action cannot be undone."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        onDelete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = milestone.isCompleted
        ? Colors.green
        : milestone.isUnlocked
            ? Theme.of(context).colorScheme.primary
            : Colors.grey;
    final Color lightColor = milestone.isCompleted
        ? Colors.green.shade100
        : milestone.isUnlocked
            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
            : Colors.grey.shade200;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(2, 80),
                painter: LinePainter(isFirst: isFirst, isLast: isLast),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor,
                ),
                child: Icon(
                  milestone.isCompleted
                      ? Icons.check_rounded
                      : milestone.isUnlocked
                          ? Icons.flag_rounded
                          : Icons.lock_rounded,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            child: Card(
              elevation: 1,
              color: lightColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: primaryColor.withOpacity(0.5)),
              ),
              child: ExpansionTile(
                enabled: milestone.isUnlocked,
                title: Text(milestone.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: milestone.isUnlocked ? null : Colors.grey)),
                // --- FIX: This is the corrected subtitle ---
                subtitle: Row(
                  children: [
                    Text(
                        'Due: ${DateFormat.yMMMd().format(milestone.deadline)}'),
                    const Spacer(),
                    if (milestone.timeSpent > Duration.zero) ...[
                      Icon(Icons.timer_outlined,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(_formatDuration(milestone.timeSpent),
                          style: TextStyle(color: Colors.grey.shade600)),
                    ]
                  ],
                ),
                // --- End of corrected subtitle ---
                trailing: milestone.isUnlocked ? null : const SizedBox.shrink(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0).copyWith(top: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (milestone.checkpoints.isNotEmpty) ...[
                          LinearProgressIndicator(
                            value: milestone.progress,
                            backgroundColor: Colors.grey.shade300,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Column(
                          children: milestone.checkpoints
                              .map((task) => CheckboxListTile(
                                    value: milestone.completedCheckpointIds
                                        .contains(task.id),
                                    title: Text(task.title,
                                        style: TextStyle(
                                            decoration: milestone
                                                    .completedCheckpointIds
                                                    .contains(task.id)
                                                ? TextDecoration.lineThrough
                                                : null)),
                                    onChanged: milestone.isUnlocked
                                        ? (val) => _confirmToggle(context, task)
                                        : null,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: primaryColor,
                                  ))
                              .toList(),
                        ),
                        if (editMode)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _confirmDelete(context),
                              child: const Text("Delete",
                                  style: TextStyle(color: Colors.red)),
                            ),
                          )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- LinePainter (Unchanged) ---
class LinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  LinePainter({required this.isFirst, required this.isLast});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2;

    if (!isFirst) {
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height / 2 - 10), paint);
    }
    if (!isLast) {
      canvas.drawLine(Offset(size.width / 2, size.height / 2 + 10),
          Offset(size.width / 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- AddMilestoneForm (MODIFIED to use new SuggestionResult) ---
class AddMilestoneForm extends StatefulWidget {
  final Function(Milestone) onAdd;
  final String goalTitle;
  const AddMilestoneForm(
      {super.key, required this.onAdd, required this.goalTitle});

  @override
  State<AddMilestoneForm> createState() => _AddMilestoneFormState();
}

class _AddMilestoneFormState extends State<AddMilestoneForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tasksController = TextEditingController();
  DateTime? _selectedDate;
  bool _dateSubmittedOnce = false;
  bool _isSuggestingTasks = false;

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _getTaskSuggestions() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please enter a milestone title first."),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isSuggestingTasks = true);
    final result = await SuggestionService.getTaskSuggestions(
        widget.goalTitle, _titleController.text.trim());
    if (mounted) {
      setState(() {
        if (result.suggestion != null) {
          try {
            // Suggestion service returns a JSON string, decode it
            final decoded = json.decode(result.suggestion!);
            final suggestions = List<String>.from(decoded['tasks']);
            if (suggestions.isNotEmpty) {
              _tasksController.text = suggestions.join('\n');
            }
          } catch (e) {
            debugPrint("Error decoding task suggestions: $e");
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Error: Could not understand AI response."),
              backgroundColor: Colors.red,
            ));
          }
        } else {
          String errorText =
              "Could not get suggestions. Please check your connection.";
          if (result.error == "NO_API_KEY") {
            errorText = "Please set your Gemini API key in Settings first.";
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorText),
            backgroundColor: Colors.red,
          ));
        }
        _isSuggestingTasks = false;
      });
    }
  }

  void _submit() {
    setState(() {
      _dateSubmittedOnce = true;
    });

    if (!_formKey.currentState!.validate() || _selectedDate == null) {
      return;
    }

    _createMilestone();
  }

  void _createMilestone() {
    final checkpoints = _tasksController.text
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((title) => Checkpoint(title: title))
        .toList();

    final newMilestone = Milestone(
      title: _titleController.text,
      deadline: _selectedDate!,
      checkpoints: checkpoints,
    );
    widget.onAdd(newMilestone);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("New Milestone",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
              validator: (value) => value == null || value.isEmpty
                  ? 'Please enter a title'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tasksController,
              decoration: const InputDecoration(
                  labelText: 'Tasks (one per line)',
                  border: OutlineInputBorder()),
              maxLines: 3,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _isSuggestingTasks
                  ? const Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(
                      onPressed: _getTaskSuggestions,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text("Suggest Tasks"),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedDate == null
                        ? 'No date chosen'
                        : 'Due: ${DateFormat.yMMMd().format(_selectedDate!)}',
                    style: TextStyle(
                      color: _selectedDate == null && _dateSubmittedOnce
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
                TextButton(
                    onPressed: _pickDate, child: const Text('Choose Date')),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Add Milestone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- FIX: Add back the missing classes that were accidentally deleted ---

class MyJourneyPage extends StatelessWidget {
  final List<Goal> allGoals;
  const MyJourneyPage({super.key, required this.allGoals});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Journey")),
      body: allGoals.isEmpty
          ? const Center(child: Text("Your journey hasn't started yet!"))
          : ListView.builder(
              itemCount: allGoals.length,
              itemBuilder: (context, index) {
                final goal = allGoals[index];
                Color color;
                IconData icon;
                final String statusText = goal.status.name[0].toUpperCase() +
                    goal.status.name.substring(1);

                switch (goal.status) {
                  case GoalStatus.active:
                    color = Colors.amber.shade700;
                    icon = Icons.flag_rounded;
                    break;
                  case GoalStatus.achieved:
                    color = Colors.green;
                    icon = Icons.check_circle_rounded;
                    break;
                  case GoalStatus.givenUp:
                    color = Colors.red;
                    icon = Icons.cancel_rounded;
                    break;
                }
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(goal.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "Set on: ${DateFormat.yMMMd().format(goal.createdAt)}"),
                    trailing: Text(statusText.toUpperCase(),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
    );
  }
}

class NotificationsSettingsPage extends StatefulWidget {
  final Goal? activeGoal;
  const NotificationsSettingsPage({super.key, this.activeGoal});

  @override
  _NotificationsSettingsPageState createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  int _notificationCount = 1;
  List<TimeOfDay> _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];
  bool _isLoading = true;
  bool _hasExactAlarmPermission = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.scheduleExactAlarm.status;

    // If permission is not granted, actively request it.
    if (status.isDenied) {
      // This will open the special "Alarms & reminders" settings screen for the user.
      status = await Permission.scheduleExactAlarm.request();
    }

    if (mounted) {
      setState(() {
        _hasExactAlarmPermission = status.isGranted;
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationCount = prefs.getInt('notification_count') ?? 1;
      final timeStrings =
          prefs.getStringList('notification_times') ?? ['09:00'];
      _notificationTimes = timeStrings.map((t) {
        final parts = t.split(':');
        return TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }).toList();
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_count', _notificationCount);
    final timeStrings =
        _notificationTimes.map((t) => '${t.hour}:${t.minute}').toList();
    await prefs.setStringList('notification_times', timeStrings);
  }

  void _updateAndSaveChanges() async {
    if (!_hasExactAlarmPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Permission denied. Cannot schedule notifications.")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final int oldNotificationCount = prefs.getInt('notification_count') ?? 0;

    for (int i = 0; i < oldNotificationCount; i++) {
      await NotificationService().cancelNotification(i);
    }

    for (int i = 0; i < _notificationCount; i++) {
      String payload = '';
      if (widget.activeGoal != null) {
        final nextMilestone = widget.activeGoal!.milestones.firstWhere(
            (m) => !m.isCompleted,
            orElse: () => Milestone(
                title: '', deadline: DateTime.now(), checkpoints: []));
        if (nextMilestone.title.isNotEmpty) {
          final nextCheckpoint = nextMilestone.checkpoints.firstWhere(
              (c) => !nextMilestone.completedCheckpointIds.contains(c.id),
              orElse: () => Checkpoint(title: ''));
          if (nextCheckpoint.title.isNotEmpty) {
            payload = json.encode({
              'goalId': widget.activeGoal!.id,
              'milestoneId': nextMilestone.id,
              'checkpointId': nextCheckpoint.id,
            });
          }
        }
      }

      await NotificationService().scheduleReminderNotification(
        id: i,
        title: 'Milestone Reminder',
        body: 'How are you doing with your goals today?',
        payload: payload,
        hour: _notificationTimes[i].hour,
        minute: _notificationTimes[i].minute,
      );
    }

    await _saveSettings();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notification settings saved!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_hasExactAlarmPermission)
                  Card(
                    color: Colors.red.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          const Text("Permission Required",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          const SizedBox(height: 8),
                          const Text(
                            "This app needs permission to schedule exact alarms for notifications to work correctly. Please grant this permission in your phone's settings.",
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                              onPressed: openAppSettings,
                              child: const Text("Open Settings"))
                        ],
                      ),
                    ),
                  ),
                Text("Number of daily reminders: $_notificationCount"),
                Slider(
                  value: _notificationCount.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: _notificationCount.toString(),
                  onChanged: (value) {
                    setState(() {
                      final newCount = value.toInt();
                      while (_notificationTimes.length < newCount) {
                        _notificationTimes
                            .add(const TimeOfDay(hour: 9, minute: 0));
                      }
                      while (_notificationTimes.length > newCount) {
                        _notificationTimes.removeLast();
                      }
                      _notificationCount = newCount;
                    });
                  },
                ),
                const Divider(),
                for (int i = 0; i < _notificationCount; i++)
                  ListTile(
                    title: Text("Reminder ${i + 1}"),
                    trailing: Text(_notificationTimes[i].format(context)),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _notificationTimes[i],
                      );
                      if (time != null) {
                        setState(() {
                          _notificationTimes[i] = time;
                        });
                      }
                    },
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _updateAndSaveChanges,
                  child: const Text("Save Settings"),
                )
              ],
            ),
    );
  }
}
