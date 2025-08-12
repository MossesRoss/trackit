import 'package:flutter/material.dart';

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

  Goal({
    required this.title,
    List<Milestone> milestones = const [],
    this.status = GoalStatus.active,
    String? id,
    DateTime? createdAt,
    this.userId,
  })  : id = id ?? UniqueKey().toString(),
        createdAt = createdAt ?? DateTime.now(),
        milestones = List<Milestone>.from(milestones);

  int get totalTasks => milestones.fold(0, (sum, m) => sum + m.checkpoints.length);
  int get completedTasks => milestones.fold(0, (sum, m) => sum + m.completedCheckpointIds.length);

  bool get isCompleted =>
      milestones.isNotEmpty && totalTasks > 0 && totalTasks == completedTasks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'userId': userId,
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'],
        title: json['title'],
        milestones: List<Milestone>.from(
            json['milestones'].map((m) => Milestone.fromJson(m))),
        status: GoalStatus.values[json['status']],
        createdAt: DateTime.parse(json['createdAt']),
        userId: json['userId'],
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
  Duration timeSpent;
  DateTime? lastWorkedOn;

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
    List<String> completedCheckpointIds = const [],
    this.isUnlocked = false,
    this.timeSpent = Duration.zero,
    this.lastWorkedOn,
    String? id,
  })  : id = id ?? UniqueKey().toString(),
        completedCheckpointIds = List<String>.from(completedCheckpointIds);

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
        'timeSpent': timeSpent.inSeconds,
        'lastWorkedOn': lastWorkedOn?.toIso8601String(),
      };

  factory Milestone.fromJson(Map<String, dynamic> json) {
    return Milestone(
      id: json['id'],
      title: json['title'],
      deadline: DateTime.parse(json['deadline']),
      checkpoints: List<Checkpoint>.from(
          json['checkpoints'].map((c) => Checkpoint.fromJson(c))),
      completedCheckpointIds:
          List<String>.from(json['completedCheckpointIds']),
      timeSpent: Duration(seconds: json['timeSpent'] ?? 0),
      lastWorkedOn: json['lastWorkedOn'] != null
          ? DateTime.parse(json['lastWorkedOn'])
          : null,
    );
  }
}

