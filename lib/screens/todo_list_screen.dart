import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../models/category.dart';
import '../database/database_helper.dart';
import 'todo_form_screen.dart';

enum StatusFilter { semua, belumSelesai, selesai }

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();

  // Sekarang pakai List<Map> karena hasil JOIN, bukan List<Todo> murni
  List<Map<String, dynamic>> _todos = [];
  List<Category> _categories = [];
  bool _isLoading = true;
  StatusFilter _statusFilter = StatusFilter.semua;
  String _searchQuery = '';
  int? _selectedCategoryId; // null = semua kategori

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadTodos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool? get _isDoneParam {
    switch (_statusFilter) {
      case StatusFilter.belumSelesai:
        return false;
      case StatusFilter.selesai:
        return true;
      case StatusFilter.semua:
        return null;
    }
  }

  Future<void> _loadCategories() async {
    final categories = await _dbHelper.getAllCategories();
    setState(() => _categories = categories);
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    final todos = await _dbHelper.getTodosWithCategory(
      isDone: _isDoneParam,
      searchQuery: _searchQuery,
      categoryId: _selectedCategoryId,
    );
    setState(() {
      _todos = todos;
      _isLoading = false;
    });
  }

  Future<void> _toggleTodo(int id, bool current) async {
    await _dbHelper.toggleTodoStatus(id, !current);
    _loadTodos();
  }

  Future<void> _deleteTodo(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Tugas'),
        content: const Text('Tugas ini akan dihapus secara permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _dbHelper.deleteTodo(id);
      _loadTodos();
    }
  }

  Future<void> _navigateToAddForm() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TodoFormScreen()),
    );
    _loadTodos();
    _loadCategories();
  }

  Future<void> _navigateToEditForm(Map<String, dynamic> todoMap) async {
    final todo = Todo.fromMap(todoMap);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TodoFormScreen(todo: todo)),
    );
    _loadTodos();
    _loadCategories();
  }

  // Dialog kecil untuk tambah kategori baru langsung dari list screen
  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori Baru'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Nama kategori'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _dbHelper.insertCategory(Category(name: name));
      _loadCategories();
    }
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'Tambah kategori',
            onPressed: _showAddCategoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Hapus semua yang selesai',
            onPressed: () async {
              await _dbHelper.clearCompletedTodos();
              _loadTodos();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Kotak pencarian ---
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari judul tugas...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadTodos();
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _loadTodos();
              },
            ),
          ),
          const SizedBox(height: 8),
          // --- Filter status ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<StatusFilter>(
              segments: const [
                ButtonSegment(value: StatusFilter.semua, label: Text('Semua')),
                ButtonSegment(
                  value: StatusFilter.belumSelesai,
                  label: Text('Belum'),
                ),
                ButtonSegment(
                  value: StatusFilter.selesai,
                  label: Text('Selesai'),
                ),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (selection) {
                setState(() => _statusFilter = selection.first);
                _loadTodos();
              },
            ),
          ),
          const SizedBox(height: 8),
          // --- Filter kategori (dropdown) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<int?>(
              initialValue: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'Filter Kategori',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Semua Kategori'),
                ),
                ..._categories.map(
                  (c) =>
                      DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedCategoryId = value);
                _loadTodos();
              },
            ),
          ),
          const SizedBox(height: 8),
          // --- Daftar tugas ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _todos.isEmpty
                ? const Center(
                    child: Text(
                      'Tidak ada tugas yang cocok.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (context, index) {
                      final todoMap = _todos[index];
                      final isDone = todoMap['isDone'] == 1;
                      final categoryName = todoMap['categoryName'] as String?;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Checkbox(
                            value: isDone,
                            onChanged: (_) =>
                                _toggleTodo(todoMap['id'] as int, isDone),
                          ),
                          title: Text(
                            todoMap['title'] as String,
                            style: TextStyle(
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDone ? Colors.grey : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((todoMap['description'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Text(todoMap['description'] as String),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(todoMap['createdAt'] as String),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              // --- Badge nama kategori ---
                              if (categoryName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Chip(
                                    label: Text(
                                      categoryName,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _navigateToEditForm(todoMap),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  size: 20,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    _deleteTodo(todoMap['id'] as int),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
