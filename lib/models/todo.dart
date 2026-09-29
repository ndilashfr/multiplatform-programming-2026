
class Todo {
  final int? id;
  final String title;
  final String? description;
  final bool isDone;
  final String createdAt;
  final String? deadline;
   final int? categoryId;

  const Todo({
    this.id,
    required this.title,
    this.description,
    this.isDone = false,
    required this.createdAt,
    this.deadline,
    this.categoryId,
  });

  // Mengonversi objek Todo menjadi Map untuk disimpan ke database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isDone': isDone ? 1 : 0,
      'createdAt': createdAt,
      'deadline': deadline,
       'categoryId': categoryId,
    };
  }

  // Mengonversi Map dari database menjadi objek Todo
  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String?,
      isDone: map['isDone'] == 1,
      createdAt: map['createdAt'] as String,
      deadline: map['deadline'] as String?,
      categoryId: map['categoryId'] as int?,
    );
  }
}
