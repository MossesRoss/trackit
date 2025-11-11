/*
 * @author Mosses
 * @version 1.5.5
 * --- CHANGELOG ---
 * v1.5.5:
 * - [FIX] Refactored `MilestoneNode` to use a `Stack` instead of a `Row`.
 * - [FIX] This resolves the "BoxConstraints forces an infinite height" crash 
 * that was happening on both MilestonesPage and GoalDetailsPage.
 * v1.5.4:
 * - [FIX] Fixed "BoxConstraints forces an infinite height" layout crash in 
 * GoalDetailsPage (Journey) by removing a nested Column inside a ListView.
 */
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import './models.dart';
import './services.dart';
import './reports_page.dart';
import './notification_service.dart';
import './guide_page.dart';
import './upgrade_page.dart';

// --- Keys for SharedPreferences Timer Recovery ---
const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';

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
  bool _isLoading = true;

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

  // --- NEW: Add didUpdateWidget to handle goal changes ---
  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the active goal ID has changed, fetch a new suggestion
    if (oldWidget.activeGoal?.id != widget.activeGoal?.id) {
      // Use postFrameCallback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchSuggestion();
        }
      });
    }
  }

  Future<void> _fetchSuggestion() async {
    setState(() => _isLoading = true);

    // --- NEW FIX ---
    // If there's no *next* milestone (either goal is new or finished),
    // we don't need to show a suggestion tip. The main UI handles this.
    if (_nextMilestone == null) {
      if (mounted) {
        setState(() {
          _suggestion = ""; // Clear any old suggestion
          _isLoading = false;
        });
      }
      return; // Don't proceed to fetch
    }
    // --- END NEW FIX ---

    final _storage = const FlutterSecureStorage();
    final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String? currentMilestoneId = _nextMilestone?.id;

    // Check cache first
    final String? cachedDate = await _storage.read(key: 'suggestion_cache_date');
    final String? cachedMilestoneId =
        await _storage.read(key: 'suggestion_cache_milestone_id');
    final String? cachedSuggestion =
        await _storage.read(key: 'suggestion_cache_content');

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

    // No valid cache, fetch new suggestion
    final result = await SuggestionService.getSuggestion(
        widget.activeGoal, _nextMilestone);

    if (mounted) {
      String textToShow;
      if (result.suggestion != null) {
        textToShow = result.suggestion!;
        // Save to cache
        await _storage.write(key: 'suggestion_cache_date', value: currentDate);
        await _storage.write(
            key: 'suggestion_cache_milestone_id', value: currentMilestoneId ?? '');
        await _storage.write(key: 'suggestion_cache_content', value: textToShow);
      } else {
        // Handle errors and get fallback
        if (result.error == "NO_API_KEY") {
          // Updated error message to be more helpful
          textToShow =
              "AI features are offline. (Dev: Check _appsScriptUrl in services.dart)";
          debugPrint("CRITICAL: _appsScriptUrl is not set in services.dart");
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
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    // --- FIX: Modify logic for empty vs. completed goals ---
                    if (widget.activeGoal!.milestones.isEmpty)
                      const Center(
                        child: Text(
                          "Goal set! Go to the Milestones page to add your first task.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontStyle: FontStyle.italic),
                        ),
                      )
                    else if (_nextMilestone == null)
                      const Center(
                        child: Text(
                          "All milestones complete! 🎉",
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    else
                      GoalTimerCircle(
                        // Pass key to update when goal time changes
                        key: ValueKey(
                            widget.activeGoal!.totalTimeSpent.inSeconds),
                        goal: widget.activeGoal!,
                        nextMilestone: _nextMilestone!,
                        onTimeAdd: widget.onTimeAdd,
                      ),
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
                                    // FIX: Replaced deprecated .withOpacity with .withAlpha
                                    ?.withAlpha((255 * 0.8).round())),
                          ),
                    const Spacer(),
                  ],
                ),
        ),
      ),
    );
  }
}

// --- Widget for the animated timer circle ---
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
      duration: const Duration(milliseconds: 750),
    )..addListener(() {
        setState(() {});
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

  void _startTimer() async {
    setState(() {
      _isTimerRunning = true;
      _showTimer = true; // Fade to timer
    });
    _animationController.value = 1.5;

    // Clear any old recovery keys before starting a new session
    final _storage = const FlutterSecureStorage();
    await _storage.delete(key: kRecoveryTimeKey);
    await _storage.delete(key: kRecoveryMilestoneKey);
    debugPrint("Timer started. Cleared old recovery keys.");

    NotificationService().showFocusNotification(
      widget.nextMilestone.title,
      json.encode({'action': 'OPEN_HOME'}),
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });

      // --- Robust Timer Save (Your Idea) ---
      // Every 5 seconds, save the current time to SharedPreferences
      if (_secondsElapsed % 5 == 0) {
        // We use .then() (fire-and-forget) so we don't 'await'
        // inside a periodic timer, which is bad practice.
        _storage.write(key: kRecoveryTimeKey, value: _secondsElapsed.toString());
        _storage.write(key: kRecoveryMilestoneKey, value: widget.nextMilestone.id);
        debugPrint("Timer recovery data saved: $_secondsElapsed seconds");
      }
    });
  }

  void _stopTimer() async {
    _timer?.cancel();
    NotificationService().cancelFocusNotification();

    // Clear the recovery keys FIRST.
    // This prevents a double-count if the app is closed right after stopping.
    final _storage = const FlutterSecureStorage();
    await _storage.delete(key: kRecoveryTimeKey);
    await _storage.delete(key: kRecoveryMilestoneKey);
    debugPrint("Timer stopped. Cleared recovery keys.");

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

  void _onLongPress() {
    if (_isTimerRunning) {
      _stopTimer();
    } else {
      _startTimer();
    }
  }

  void _onTap() {
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

  // --- FIX: This function is now accurate (from v1.3.1) ---
  String _formatTotalTime(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    }
    if (duration.inMinutes > 0) {
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    }
    if (duration.inSeconds > 0) {
      return "${duration.inSeconds}s";
    }
    // Default for 0
    return "0m 0s";
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

    // --- FEAT: Build RichText for total time display ---
    final String totalTimeText = _formatTotalTime(widget.goal.totalTimeSpent);
    final double fontSize = totalTimeText.length > 8 ? 30 : 36; // Adjusted size

    final TextStyle numberStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: primaryColor,
    );
    // Style for 'h', 'm', 's' with reduced opacity
    final TextStyle unitStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      color: primaryColor.withOpacity(0.5), // <-- Reduced opacity
    );

    final List<TextSpan> spans = [];
    final RegExp simpleRegex = RegExp(r'(\d+)([hms])');
    final parts =
        totalTimeText.split(' '); // e.g., ["4h", "47m"] or ["0m", "0s"]

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final match = simpleRegex.firstMatch(part); // Match "4h", "47m", etc.

      if (match != null) {
        // Add number (e.g., "4")
        spans.add(TextSpan(text: match.group(1), style: numberStyle));
        // Add unit (e.g., "h")
        spans.add(TextSpan(text: match.group(2), style: unitStyle));
        // Add space if not the last part
        if (i < parts.length - 1) {
          spans.add(TextSpan(text: ' ', style: numberStyle));
        }
      } else {
        // Fallback just in case
        spans.add(TextSpan(text: part, style: numberStyle));
      }
    }
    // --- End of RichText build ---

    return GestureDetector(
      onLongPress: _onLongPress,
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
                // --- FIX: Use theme-aware color ---
                backgroundColor: Theme.of(context).dividerColor,
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
              secondChild: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: spans,
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

// --- MilestonesPage (MODIFIED) ---
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

// --- FIX: Add SingleTickerProviderStateMixin for animation ---
class MilestonesPageState extends State<MilestonesPage>
    with SingleTickerProviderStateMixin {
  // --- NEW: Animation controller for the '+' icon ---
  late AnimationController _iconAnimationController;
  late Animation<double> _iconAnimation;

  @override
  void initState() {
    super.initState();
    // --- NEW: Initialize animation ---
    _iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _iconAnimation = Tween(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(
        parent: _iconAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // --- NEW: Start animation only if milestones are empty ---
    // This runs ONCE on first load
    if (widget.activeGoal != null && widget.activeGoal!.milestones.isEmpty) {
      _iconAnimationController.repeat(reverse: true);
    }
  }

  // --- NEW: Add didUpdateWidget to handle goal changes ---
  @override
  void didUpdateWidget(covariant MilestonesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check animation logic when the widget's goal changes
    if (widget.activeGoal != null && widget.activeGoal!.milestones.isEmpty) {
      // Goal is active and empty, start animation
      _iconAnimationController.repeat(reverse: true);
    } else {
      // Goal is null or has milestones, stop animation
      _iconAnimationController.stop();
      _iconAnimationController.reset(); // Reset to normal size
    }
  }

  @override
  void dispose() {
    // --- NEW: Dispose controller ---
    _iconAnimationController.dispose();
    super.dispose();
  }

  void showAddMilestoneDialog(BuildContext context) {
    // --- NEW: Stop animation when button is pressed ---
    _iconAnimationController.stop();
    _iconAnimationController.reset(); // --- NEW: Reset scale ---

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
    // --- FIX: Get line color from theme ---
    final Color lineColor = Theme.of(context).dividerColor;

    // --- FIX: Sorting logic ---
    List<Milestone> sortedMilestones = [];
    if (widget.activeGoal != null && widget.activeGoal!.milestones.isNotEmpty) {
      final milestones = widget.activeGoal!.milestones;

      List<Milestone> completed = [];
      List<Milestone> upcoming = [];
      Milestone? currentMilestone;

      // Find the first incomplete milestone
      try {
        currentMilestone = milestones.firstWhere((m) => !m.isCompleted);
      } catch (e) {
        currentMilestone = null;
      }

      // Separate lists
      for (final milestone in milestones) {
        if (milestone.isCompleted) {
          completed.add(milestone);
        } else {
          // Add current milestone to the front of upcoming
          if (currentMilestone != null && milestone.id == currentMilestone.id) {
            upcoming.insert(0, milestone);
          } else {
            upcoming.add(milestone);
          }
        }
      }

      // Combine lists
      sortedMilestones = upcoming + completed;
    }
    // --- End of fix ---

    return Scaffold(
      appBar: AppBar(
        title: const Text('Milestones'),
        actions: [
          if (widget.editMode && widget.activeGoal != null)
            // --- NEW: Wrap icon button in animation ---
            ScaleTransition(
              scale: _iconAnimation,
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () => showAddMilestoneDialog(context),
                tooltip: 'Add Milestone',
              ),
            ),
        ],
      ),
      body: widget.activeGoal == null
          ? const Center(child: Text("Set a main goal on the Home page first."))
          : widget.activeGoal!.milestones.isEmpty
              // --- NEW: Updated empty state UI ---
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      "Your goal is set!\n\nTap the '+' button above to add your first milestone.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            height: 1.5,
                          ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  // --- FIX: Use sorted list ---
                  itemCount: sortedMilestones.length,
                  itemBuilder: (context, index) {
                    final milestone = sortedMilestones[index];
                    // --- End of fix ---

                    // --- FIX v1.4.5: Wrap in IntrinsicHeight to solve layout crash ---
                    // --- FIX v1.5.1: Removed IntrinsicHeight to fix overflow/jank on expand
                    return MilestoneNode(
                      key: ValueKey('${milestone.id}-${milestone.progress}'),
                      milestone: milestone,
                      // --- FIX: Use sorted list for first/last ---
                      isFirst: index == 0,
                      isLast: index == sortedMilestones.length - 1,
                      // --- End of fix ---
                      onToggleCheckpoint: widget.onToggleCheckpoint,
                      onDelete: () => widget.onDeleteMilestone(milestone.id),
                      editMode: widget.editMode,
                      lineColor: lineColor, // --- FIX: Pass line color ---
                    );
                  },
                ),
    );
  }
}

// --- SettingsPage (MODIFIED) ---
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

  // // --- _launchURL method (unchanged) ---
  // Future<void> _launchURL(String urlString) async {
  //   final Uri url = Uri.parse(urlString);
  //   if (!await launchUrl(url)) {
  //     throw Exception('Could not launch $url');
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    // Find the active goal to pass to ReportsPage
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
          // --- MOD: "Upgrade to Pro" Tile ---
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.auto_awesome_rounded,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              title: Text(
                "Upgrade to Pro",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              subtitle: Text(
                "Unlock AI features & more!",
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimaryContainer
                      .withOpacity(0.8),
                ),
              ),
              // --- MOD: Changed onTap to navigate to the new page ---
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const UpgradePage(),
                ));
              },
            ),
          ),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.assessment_rounded),
            title: const Text("Reports"),
            subtitle: const Text("View your weekly and monthly progress"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                // Pass the activeGoal to ReportsPage
                // This is the NEW, correct code
                builder: (_) => const ReportsPage())),
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
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text("Help"),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GuidePage())),
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

// --- GetInTouchPage (Unchanged) ---
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

// --- MilestoneNode (FIXED v1.5.5) ---
class MilestoneNode extends StatelessWidget {
  final Milestone milestone;
  final bool isFirst;
  final bool isLast;
  final Function(Milestone, String) onToggleCheckpoint;
  final VoidCallback onDelete;
  final bool editMode;
  final Color lineColor; // --- FIX: Added line color ---

  const MilestoneNode(
      {super.key,
      required this.milestone,
      required this.isFirst,
      required this.isLast,
      required this.onToggleCheckpoint,
      required this.onDelete,
      required this.editMode,
      required this.lineColor // --- FIX: Added line color ---
      });

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

    // --- FIX: Use theme-aware colors for dark mode ---
    final Color lightColor;
    if (milestone.isCompleted) {
      lightColor = Colors.green.withOpacity(0.1);
    } else if (milestone.isUnlocked) {
      lightColor = Theme.of(context).colorScheme.primary.withOpacity(0.1);
    } else {
      // FIX: Replaced deprecated .surfaceVariant with .surfaceContainerHighest
      lightColor = Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withOpacity(0.5);
    }

    final Color? subtitleColor = milestone.isUnlocked
        ? Theme.of(context).textTheme.bodySmall?.color
        : Theme.of(context).disabledColor;

    // ---
    // --- FIX v1.5.5: Refactored to use Stack instead of Row ---
    // This solves the "infinite height" constraint error in ListViews.
    // ---
    return Stack(
      children: [
        // --- Child 1: The Timeline Painter (Positioned) ---
        // This is positioned to the left and stretches vertically
        // to the height of the Stack (which is set by Child 2).
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 40,
          child: CustomPaint(
            painter: LinePainter(
              isFirst: isFirst,
              isLast: isLast,
              lineColor: lineColor,
              dotColor: primaryColor, // Pass color
              icon: milestone.isCompleted
                  ? Icons.check_rounded
                  : milestone.isUnlocked
                      ? Icons.flag_rounded
                      : Icons.lock_rounded,
            ),
          ),
        ),
        // --- Child 2: The Content (Padded) ---
        // This is the main content card. It is NOT positioned,
        // so its height determines the Stack's height.
        Padding(
          padding: const EdgeInsets.only(left: 40.0),
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
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(milestone.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: milestone.isUnlocked
                            ? null
                            : Theme.of(context).disabledColor)),
                subtitle: Row(
                  children: [
                    Text(
                      'Due: ${DateFormat.yMMMd().format(milestone.deadline)}',
                      // --- FIX: Use theme-aware disabled color ---
                      style: TextStyle(
                          color: milestone.isUnlocked
                              ? null
                              : Theme.of(context).disabledColor),
                    ),
                    const Spacer(),
                    if (milestone.timeSpent > Duration.zero) ...[
                      // --- FIX: Use theme-aware disabled color ---
                      Icon(Icons.timer_outlined,
                          size: 14, color: subtitleColor),
                      const SizedBox(width: 4),
                      Text(_formatDuration(milestone.timeSpent),
                          // --- FIX: Use theme-aware disabled color ---
                          style: TextStyle(color: subtitleColor)),
                    ]
                  ],
                ),
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
                            // --- FIX: Use theme-aware color ---
                            backgroundColor: Theme.of(context).dividerColor,
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

// --- LinePainter (FIXED Dark Mode & Dynamic Height) ---
class LinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final Color lineColor;
  final Color dotColor;
  final IconData icon;

  // Define a fixed vertical position for the dot
  final double dotY = 40.0; // This is the center of the dot
  final double dotRadius = 10.0;
  final double iconSize = 12.0;

  LinePainter({
    required this.isFirst,
    required this.isLast,
    required this.lineColor,
    required this.dotColor,
    required this.icon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;

    // --- 1. Draw the vertical lines ---
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2;

    if (!isFirst) {
      // Draw top line
      canvas.drawLine(
          Offset(centerX, 0), Offset(centerX, dotY - dotRadius), paint);
    }
    if (!isLast) {
      // Draw bottom line
      canvas.drawLine(Offset(centerX, dotY + dotRadius),
          Offset(centerX, size.height), paint);
    }

    // --- 2. Draw the dot ---
    final dotPaint = Paint()..color = dotColor;
    canvas.drawCircle(Offset(centerX, dotY), dotRadius, dotPaint);

    // --- 3. Draw the icon ---
    final textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr, // <-- FIX: Used 'ui.' prefix
    );
    final iconColor = Colors.white; // Icon is always white

    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        color: iconColor,
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
      ),
    );

    textPainter.layout();
    // Center the icon inside the dot
    final iconOffset = Offset(
      centerX - textPainter.width / 2,
      dotY - textPainter.height / 2,
    );
    textPainter.paint(canvas, iconOffset);
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) {
    // Check if any property changed
    return oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.icon != icon;
  }
}

// --- AddMilestoneForm (Unchanged) ---
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
            errorText = "AI features are offline. (Dev: Check Apps Script URL)";
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

// --- MyJourneyPage (UPDATED with navigation) ---
class MyJourneyPage extends StatelessWidget {
  final List<Goal> allGoals;
  const MyJourneyPage({super.key, required this.allGoals});

  @override
  Widget build(BuildContext context) {
    // Sort goals so active one is at the top
    List<Goal> sortedGoals = List.from(allGoals);
    sortedGoals.sort((a, b) {
      if (a.status == GoalStatus.active) return -1;
      if (b.status == GoalStatus.active) return 1;
      return b.createdAt.compareTo(a.createdAt); // Show newest first
    });

    return Scaffold(
      appBar: AppBar(title: const Text("My Journey")),
      body: sortedGoals.isEmpty
          ? const Center(child: Text("Your journey hasn't started yet!"))
          : ListView.builder(
              itemCount: sortedGoals.length,
              itemBuilder: (context, index) {
                final goal = sortedGoals[index];
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
                  // --- NEW: Wrap in InkWell for tap ---
                  child: InkWell(
                    onTap: () {
                      // --- NEW: Navigate to details page ---
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GoalDetailsPage(goal: goal),
                      ));
                    },
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
                  ),
                );
              },
            ),
    );
  }
}

// --- NEW: GoalDetailsPage (for immutable view) ---
class GoalDetailsPage extends StatelessWidget {
  final Goal goal;
  const GoalDetailsPage({super.key, required this.goal});

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    }
    if (duration.inMinutes > 0) {
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    }
    return "${duration.inSeconds}s";
  }

  @override
  Widget build(BuildContext context) {
    final Color lineColor = Theme.of(context).dividerColor;

    // Determine status color and icon
    Color statusColor;
    IconData statusIcon;
    final String statusText =
        goal.status.name[0].toUpperCase() + goal.status.name.substring(1);

    switch (goal.status) {
      case GoalStatus.active:
        statusColor = Colors.amber.shade700;
        statusIcon = Icons.flag_rounded;
        break;
      case GoalStatus.achieved:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case GoalStatus.givenUp:
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- Goal Summary Card ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Goal Summary",
                      style: Theme.of(context).textTheme.titleLarge),
                  const Divider(height: 24),
                  _DetailRow(
                    icon: statusIcon,
                    iconColor: statusColor,
                    title: "Status",
                    value: statusText,
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    title: "Created On",
                    value: DateFormat.yMMMd().format(goal.createdAt),
                  ),
                  _DetailRow(
                    icon: Icons.timer_rounded,
                    title: "Total Time Spent",
                    value: _formatDuration(goal.totalTimeSpent),
                  ),
                  _DetailRow(
                    icon: Icons.task_alt_rounded,
                    title: "Tasks Completed",
                    value: "${goal.completedTasks} / ${goal.totalTasks}",
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text("Milestones", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          // --- Immutable Milestone List ---
          // ---
          // --- FIX v1.5.4: Replaced Column with ...spread operator ---
          // This prevents the "infinite height" layout crash.
          // ---
          if (goal.milestones.isEmpty)
            const Center(
              child: Text("No milestones were added for this goal."),
            )
          else
            ...goal.milestones.map((milestone) {
              final index = goal.milestones.indexOf(milestone);
              return MilestoneNode(
                key: ValueKey(milestone.id),
                milestone: milestone,
                isFirst: index == 0,
                isLast: index == goal.milestones.length - 1,
                // --- Pass dummy/empty functions to make it read-only ---
                onToggleCheckpoint: (m, c) {}, // Does nothing
                onDelete: () {}, // Does nothing
                editMode: false, // Disables delete button and toggle logic
                lineColor: lineColor,
              );
            }),
        ],
      ),
    );
  }
}

// --- NEW: Helper widget for GoalDetailsPage ---
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? iconColor;

  const _DetailRow(
      {required this.icon,
      required this.title,
      required this.value,
      this.iconColor});

  @override
  Widget build(context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon,
              color: iconColor ?? Theme.of(context).colorScheme.primary,
              size: 20),
          const SizedBox(width: 16),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// --- NotificationsSettingsPage (Unchanged) ---
class NotificationsSettingsPage extends StatefulWidget {
  final Goal? activeGoal;
  const NotificationsSettingsPage({super.key, this.activeGoal});

  @override
  // FIX: Made state class public to resolve private_type_in_public_api lint
  NotificationsSettingsPageState createState() =>
      NotificationsSettingsPageState();
}

// FIX: Made state class public
class NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  int _notificationCount = 1;
  List<TimeOfDay> _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];
  bool _isLoading = true;
  bool _hasExactAlarmPermission = false;

  final _storage = const FlutterSecureStorage();

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
    final notificationCountString =
        await _storage.read(key: 'notification_count');
    final timeStringsJson = await _storage.read(key: 'notification_times');

    setState(() {
      _notificationCount =
          notificationCountString != null ? int.parse(notificationCountString) : 1;
      if (timeStringsJson != null) {
        final List<String> timeStrings = List<String>.from(json.decode(timeStringsJson));
        _notificationTimes = timeStrings.map((t) {
          final parts = t.split(':');
          return TimeOfDay(
              hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }).toList();
      } else {
        _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];
      }
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await _storage.write(
        key: 'notification_count', value: _notificationCount.toString());
    final timeStrings =
        _notificationTimes.map((t) => '${t.hour}:${t.minute}').toList();
    await _storage.write(key: 'notification_times', value: json.encode(timeStrings));
  }

  void _updateAndSaveChanges() async {
    if (!_hasExactAlarmPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Permission denied. Cannot schedule notifications.")));
      return;
    }

    final oldNotificationCountString =
        await _storage.read(key: 'notification_count');
    final int oldNotificationCount =
        oldNotificationCountString != null ? int.parse(oldNotificationCountString) : 0;

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
                    child: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Text("Permission Required",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          SizedBox(height: 8),
                          Text(
                            "This app needs permission to schedule exact alarms for notifications to work correctly. Please grant this permission in your phone's settings.",
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          TextButton(
                              onPressed: openAppSettings,
                              child: Text("Open Settings"))
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
