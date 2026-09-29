import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/todo.dart';
import '../models/category.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'todo.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tabel categories dibuat duluan karena todos merujuk ke sini (FK)
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        isDone INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        deadline TEXT,
        categoryId INTEGER,
        FOREIGN KEY (categoryId) REFERENCES categories (id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE todos ADD COLUMN deadline TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL
        )
      ''');
      await db.execute('ALTER TABLE todos ADD COLUMN categoryId INTEGER');
    }
  }

  Future<int> insertTodo(Todo todo) async {
    try {
      final db = await database;
      return await db.insert(
        'todos',
        todo.toMap(),
        conflictAlgorithm:
            ConflictAlgorithm.replace, // Mengganti jika ada duplikasi ID
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw Exception('Tugas dengan data yang sama sudah ada.');
      }
      throw Exception('Gagal menyimpan tugas: ${e.toString()}');
    }
  }

  Future<void> insertTodoWithLog(Todo todo, String logMessage) async {
    final db = await database;
    await db.transaction((txn) async {
      // Operasi pertama: simpan tugas baru
      await txn.insert('todos', todo.toMap());

      // Operasi kedua: catat log aktivitas
      await txn.insert('activity_logs', {
        'message': logMessage,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Jika salah satu operasi di atas gagal, seluruh transaksi dibatalkan
    });
  }

  Future<List<Todo>> getAllTodos() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'todos',
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Todo.fromMap(maps[i]));
  }

  Future<Todo?> getTodoById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'todos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Todo.fromMap(maps.first);
  }

  Future<void> updateTodo(Todo todo) async {
    final db = await database;
    await db.update(
      'todos',
      todo.toMap(),
      where: 'id = ?',
      whereArgs: [todo.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> toggleTodoStatus(int id, bool isDone) async {
    final db = await database;
    return await db.update(
      'todos',
      {'isDone': isDone ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTodo(int id) async {
    final db = await database;
    await db.delete('todos', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearCompletedTodos() async {
    final db = await database;
    return await db.delete('todos', where: 'isDone = ?', whereArgs: [1]);
  }

  Future<void> closeDatabase() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // Mengambil tugas dengan filter status dan/atau kata kunci pencarian
  Future<List<Todo>> getFilteredTodos({
    bool? isDone, // null = semua status, true = selesai, false = belum
    String? searchQuery, // null/kosong = tanpa filter judul
  }) async {
    final db = await database;

    final List<String> conditions = [];
    final List<dynamic> args = [];

    if (isDone != null) {
      conditions.add('isDone = ?');
      args.add(isDone ? 1 : 0);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('title LIKE ?');
      args.add('%${searchQuery.trim()}%');
    }

    final maps = await db.query(
      'todos',
      where: conditions.isNotEmpty ? conditions.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'createdAt DESC',
    );

    return List.generate(maps.length, (i) => Todo.fromMap(maps[i]));
  }

  // ---------- CRUD Kategori ----------

  Future<int> insertCategory(Category category) async {
    final db = await database;
    return await db.insert('categories', category.toMap());
  }

  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final maps = await db.query('categories', orderBy: 'name ASC');
    return List.generate(maps.length, (i) => Category.fromMap(maps[i]));
  }

  Future<int> updateCategory(Category category) async {
    final db = await database;
    return await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    // Lepas keterkaitan todos yang pakai kategori ini biar nggak jadi data yatim
    await db.update(
      'todos',
      {'categoryId': null},
      where: 'categoryId = ?',
      whereArgs: [id],
    );
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Query gabungan: todos + nama kategori + filter kategori ----------
  // Pakai rawQuery karena query() biasa nggak bisa JOIN antar tabel (jawaban Soal 1)
  Future<List<Map<String, dynamic>>> getTodosWithCategory({
    bool? isDone,
    String? searchQuery,
    int? categoryId,
  }) async {
    final db = await database;
    final List<String> conditions = [];
    final List<dynamic> args = [];

    if (isDone != null) {
      conditions.add('t.isDone = ?');
      args.add(isDone ? 1 : 0);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('t.title LIKE ?');
      args.add('%${searchQuery.trim()}%');
    }
    if (categoryId != null) {
      conditions.add('t.categoryId = ?');
      args.add(categoryId);
    }

    final whereClause = conditions.isNotEmpty
        ? 'WHERE ${conditions.join(' AND ')}'
        : '';

    return await db.rawQuery('''
      SELECT t.*, c.name AS categoryName
      FROM todos t
      LEFT JOIN categories c ON t.categoryId = c.id
      $whereClause
      ORDER BY t.createdAt DESC
    ''', args);
  }
}

// Menutup koneksi database secara eksplisit
