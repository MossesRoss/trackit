import 'package:flutter/material.dart';

// Enum for the status of a goal.
enum GoalStatus { active, achieved, givenUp }

// Represents a single checkpoint or task within a milestone.
class Checkpoint {
  final String id;
  final String title;

  Checkpoint({required this.title}) : id = UniqueKey().toString();

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(title: json['title']);
}

// Represents a major goal in the application.
class Goal {
  String id;
  String title;
  List<Milestone> milestones;
  GoalStatus status;
  DateTime createdAt;

  Goal({
    required this.title,
    List<Milestone> milestones = const [],
    this.status = GoalStatus.active,
    String? id,
    DateTime? createdAt,
  })  : id = id ?? UniqueKey().toString(),
        createdAt = createdAt ?? DateTime.now(),
        milestones = List<Milestone>.from(milestones);

  int get totalTasks => milestones.isEmpty ? 0 : milestones.map((m) => m.checkpoints.length).reduce((a, b) => a + b);
  int get completedTasks => milestones.isEmpty ? 0 : milestones.map((m) => m.completedCheckpointIds.length).reduce((a, b) => a + b);
  bool get isCompleted => milestones.isNotEmpty && milestones.every((m) => m.isCompleted);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'milestones': milestones.map((m) => m.toJson()).toList(),
    'status': status.index,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'],
    title: json['title'],
    milestones: List<Milestone>.from(json['milestones'].map((m) => Milestone.fromJson(m))),
    status: GoalStatus.values[json['status']],
    createdAt: DateTime.parse(json['createdAt']),
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

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
    List<String> completedCheckpointIds = const [],
    this.isUnlocked = false,
    this.timeSpent = Duration.zero,
    String? id,
  }) : id = id ?? UniqueKey().toString(),
       completedCheckpointIds = List<String>.from(completedCheckpointIds);

  double get progress => checkpoints.isEmpty ? 0.0 : completedCheckpointIds.length / checkpoints.length;
  bool get isCompleted => progress == 1.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'deadline': deadline.toIso8601String(),
    'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
    'completedCheckpointIds': completedCheckpointIds,
    'timeSpent': timeSpent.inSeconds,
  };

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
    id: json['id'],
    title: json['title'],
    deadline: DateTime.parse(json['deadline']),
    checkpoints: List<Checkpoint>.from(json['checkpoints'].map((c) => Checkpoint.fromJson(c))),
    completedCheckpointIds: List<String>.from(json['completedCheckpointIds']),
    timeSpent: Duration(seconds: json['timeSpent']),
  );
}

