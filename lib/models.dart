/*
 * @author Mosses
 * @version 1.5.0
 * --- CHANGELOG ---
 * v1.5.0:
 * - [FEAT] Added 'completedAt' timestamp to Milestone model to track 
 * completion dates for the weekly email report.
 * v1.4.0:
 * - [FEAT] Added `TimeSession` class to log individual work sessions
 * with timestamps, enabling accurate period-based reporting.
 * - [FEAT] Added `timeLog` (a List<TimeSession>) to the `Milestone` model.
 * - [FIX] `Milestone.timeSpent` and `Milestone.lastWorkedOn` are now getters
 * that compute their values from the `timeLog`.
 * - [FIX] `Milestone.fromJson` now intelligently migrates old `timeSpent`
 * data into the new `timeLog` model, ensuring backward compatibility.
 * - [FIX] `Milestone.toJson` now saves the new `timeLog`.
 */
import 'package:flutter/material.dart';

// --- NEW: Enum for the status of a task check-in ---
enum TaskCheckinStatus { done, doing, willDo, wontDo }

// --- NEW: Represents a single check-in response from a notification ---
class TaskCheckin {
  final String checkpointId;
  final TaskCheckinStatus status;
  final DateTime timestamp;

  TaskCheckin({
    required this.checkpointId,
    required this.status,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'checkpointId': checkpointId,
        'status': status.index,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TaskCheckin.fromJson(Map<String, dynamic> json) => TaskCheckin(
        checkpointId: json['checkpointId'],
        status: TaskCheckinStatus.values[json['status']],
        timestamp: DateTime.parse(json['timestamp']),
      );
}

// --- NEW: Represents a single timed work session ---
class TimeSession {
  final DateTime timestamp;
  final Duration duration;

  TimeSession({
    required this.timestamp,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'durationInSeconds': duration.inSeconds,
      };

  factory TimeSession.fromJson(Map<String, dynamic> json) => TimeSession(
        timestamp: DateTime.parse(json['timestamp']),
        duration: Duration(seconds: json['durationInSeconds']),
      );
}

// Enum for the status of a goal.
enum GoalStatus { active, achieved, givenUp }

// Represents a single checkpoint or task within a milestone.
class Checkpoint {
  final String id;
  final String title;

  Checkpoint({required this.title, String? id}) : id = id ?? UniqueKey().toString();

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory Checkpoint.fromJson(Map<String, dynamic> json) =>
      Checkpoint(title: json['title'], id: json['id']);
}

// Represents a major goal in the application.
class Goal {
  String id;
  String title;
  List<Milestone> milestones;
  GoalStatus status;
  DateTime createdAt;
  String? userId;
  // --- NEW: Flag to indicate if the goal has been archived ---
  bool isArchived;

  Goal({
    required this.title,
    List<Milestone> milestones = const [],
    this.status = GoalStatus.active,
    String? id,
    DateTime? createdAt,
    this.userId,
    this.isArchived = false, // Default to not archived
  })  : id = id ?? UniqueKey().toString(),
        createdAt = createdAt ?? DateTime.now(),
        milestones = List<Milestone>.from(milestones);

  int get totalTasks => milestones.fold(0, (sum, m) => sum + m.checkpoints.length);
  int get completedTasks => milestones.fold(0, (sum, m) => sum + m.completedCheckpointIds.length);

  // --- FIX: totalTimeSpent now computes from the new milestone log ---
  Duration get totalTimeSpent =>
      milestones.fold(Duration.zero, (sum, m) => sum + m.timeSpent);

  bool get isCompleted =>
      milestones.isNotEmpty && totalTasks > 0 && totalTasks == completedTasks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'userId': userId,
        'isArchived': isArchived,
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'],
        title: json['title'],
        milestones: List<Milestone>.from(
            (json['milestones'] as List).map((m) => Milestone.fromJson(m))),
        status: GoalStatus.values[json['status']],
        createdAt: DateTime.parse(json['createdAt']),
        userId: json['userId'],
        isArchived: json['isArchived'] ?? false,
      );
}

// Represents a milestone within a larger goal.
class Milestone {
  String id;
  String title;
  DateTime deadline;
  List<Checkpoint> checkpoints;
  List<String> completedCheckpointIds;
  bool isUnlocked;
  // --- FIX: timeSpent and lastWorkedOn are replaced by timeLog ---
  // Duration timeSpent;
  // DateTime? lastWorkedOn;
  List<TimeSession> timeLog;
  // --- NEW: List to store task check-in records ---
  List<TaskCheckin> checkins;
  // --- NEW (v1.5.0): Timestamp for when the milestone was completed ---
  DateTime? completedAt;

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
    List<String> completedCheckpointIds = const [],
    this.isUnlocked = false,
    // --- FIX: Remove timeSpent and lastWorkedOn from constructor ---
    // this.timeSpent = Duration.zero,
    // this.lastWorkedOn,
    String? id,
    List<TaskCheckin> checkins = const [], // Initialize with empty list
    List<TimeSession> timeLog = const [], // --- FIX: Add timeLog ---
    this.completedAt, // --- NEW (v1.5.0) ---
  })  : id = id ?? UniqueKey().toString(),
        completedCheckpointIds = List<String>.from(completedCheckpointIds),
        checkins = List<TaskCheckin>.from(checkins),
        timeLog = List<TimeSession>.from(timeLog); // --- FIX: Add timeLog ---

  // --- FIX: timeSpent is now a getter that sums the log ---
  Duration get timeSpent =>
      timeLog.fold(Duration.zero, (prev, session) => prev + session.duration);

  // --- FIX: lastWorkedOn is now a getter that checks the log ---
  DateTime? get lastWorkedOn => timeLog.isEmpty ? null : timeLog.last.timestamp;

  double get progress => checkpoints.isEmpty
      ? 0.0
      : completedCheckpointIds.length / checkpoints.length;
  bool get isCompleted => checkpoints.isNotEmpty && progress == 1.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'deadline': deadline.toIso8601String(),
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'completedCheckpointIds': completedCheckpointIds,
        // --- FIX: Save the new timeLog instead of old fields ---
        // 'timeSpent': timeSpent.inSeconds,
        // 'lastWorkedOn': lastWorkedOn?.toIso8601String(),
        'timeLog': timeLog.map((s) => s.toJson()).toList(),
        'checkins': checkins.map((c) => c.toJson()).toList(),
        'completedAt': completedAt?.toIso8601String(), // --- NEW (v1.5.0) ---
      };

  factory Milestone.fromJson(Map<String, dynamic> json) {
    // --- FIX: Add migration logic for old data model ---
    List<TimeSession> log = [];
    if (json['timeLog'] != null) {
      // New data model exists, use it
      log = List<TimeSession>.from(
          (json['timeLog'] as List).map((s) => TimeSession.fromJson(s)));
    } else if ((json['timeSpent'] ?? 0) > 0) {
      // Old data model exists, migrate it to a single session
      log.add(TimeSession(
        timestamp: json['lastWorkedOn'] != null
            ? DateTime.parse(json['lastWorkedOn'])
            : DateTime.now(), // Fallback timestamp
        duration: Duration(seconds: json['timeSpent'] ?? 0),
      ));
    }
    // --- End of migration logic ---

    return Milestone(
      id: json['id'],
      title: json['title'],
      deadline: DateTime.parse(json['deadline']),
      checkpoints: List<Checkpoint>.from(
          (json['checkpoints'] as List).map((c) => Checkpoint.fromJson(c))),
      completedCheckpointIds:
          List<String>.from(json['completedCheckpointIds']),
      // --- FIX: Remove old fields from factory ---
      // timeSpent: Duration(seconds: json['timeSpent'] ?? 0),
      // lastWorkedOn: json['lastWorkedOn'] != null
      //     ? DateTime.parse(json['lastWorkedOn'])
      //     : null,
      timeLog: log, // --- FIX: Assign the new log ---
      // Handle potentially null check-ins for backward compatibility
      checkins: json['checkins'] == null
          ? []
          : List<TaskCheckin>.from(
              (json['checkins'] as List).map((c) => TaskCheckin.fromJson(c))),
      // --- NEW (v1.5.0) ---
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}