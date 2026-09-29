import 'package:flutter/material.dart';
import '../models/todo.dart';
import '../models/category.dart';
import '../database/database_helper.dart';

class TodoFormScreen extends StatefulWidget {
  final Todo? todo;

  const TodoFormScreen({super.key, this.todo});

  @override
  State<TodoFormScreen> createState() => _TodoFormScreenState();
}

class _TodoFormScreenState extends State<TodoFormScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  DateTime? _selectedDeadline;
  int? _selectedCategoryId;
  List<Category> _categories = [];
  bool _isLoadingCategories = true;

  bool get _isEditMode => widget.todo != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _titleController.text = widget.todo!.title;
      _descController.text = widget.todo!.description ?? '';
      _selectedCategoryId = widget.todo!.categoryId;
      if (widget.todo!.deadline != null) {
        _selectedDeadline = DateTime.tryParse(widget.todo!.deadline!);
      }
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _dbHelper.getAllCategories();
    setState(() {
      _categories = categories;
      _isLoadingCategories = false;
    });
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDeadline = picked);
    }
  }

  // Dialog cepat untuk menambah kategori baru tanpa keluar dari form
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
      final newId = await _dbHelper.insertCategory(Category(name: name));
      await _loadCategories();
      setState(() => _selectedCategoryId = newId);
    }
  }

  Future<void> _saveTodo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final deadlineString = _selectedDeadline?.toIso8601String();

      if (_isEditMode) {
        final updatedTodo = Todo(
          id: widget.todo!.id,
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          isDone: widget.todo!.isDone,
          createdAt: widget.todo!.createdAt,
          deadline: deadlineString,
          categoryId: _selectedCategoryId,
        );
        await _dbHelper.updateTodo(updatedTodo);
      } else {
        final newTodo = Todo(
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          createdAt: DateTime.now().toIso8601String(),
          deadline: deadlineString,
          categoryId: _selectedCategoryId,
        );
        await _dbHelper.insertTodo(newTodo);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan tugas: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? 'Edit Tugas' : 'Tambah Tugas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Judul Tugas',
                  hintText: 'Masukkan judul tugas',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Judul tugas tidak boleh kosong';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi (opsional)',
                  hintText: 'Masukkan deskripsi tugas',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              // --- Pemilih deadline ---
              InkWell(
                onTap: _pickDeadline,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Deadline (opsional)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _selectedDeadline == null
                        ? 'Belum dipilih'
                        : '${_selectedDeadline!.day}/${_selectedDeadline!.month}/${_selectedDeadline!.year}',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // --- Pemilih kategori ---
              _isLoadingCategories
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            initialValue: _selectedCategoryId,
                            decoration: const InputDecoration(
                              labelText: 'Kategori (opsional)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Tanpa Kategori'),
                              ),
                              ..._categories.map(
                                (c) => DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedCategoryId = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          tooltip: 'Tambah kategori baru',
                          onPressed: _showAddCategoryDialog,
                        ),
                      ],
                    ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveTodo,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditMode ? 'Simpan Perubahan' : 'Tambah Tugas'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}