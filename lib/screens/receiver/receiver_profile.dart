import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class ReceiverProfileScreen extends StatefulWidget {
  const ReceiverProfileScreen({super.key});

  @override
  State<ReceiverProfileScreen> createState() => _ReceiverProfileScreenState();
}

class _ReceiverProfileScreenState extends State<ReceiverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _areaController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _areaController = TextEditingController(text: user?.area ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: _areaController,
                    decoration: const InputDecoration(labelText: 'Primary Location'),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Contact Phone'),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  Navigator.pop(context); // close dialog
                  try {
                    await context.read<AuthProvider>().updateProfile({
                      'name': _nameController.text.trim(),
                      'area': _areaController.text.trim(),
                      'phone': _phoneController.text.trim(),
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Update failed: $e')),
                      );
                    }
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final isLoading = context.watch<AuthProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.errorColor),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.p24),
              child: Column(
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: AppTheme.accentColor.withOpacity(0.1),
                          child: const Icon(Icons.person, size: 50, color: AppTheme.accentColor),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(user?.name ?? 'Guest User', style: Theme.of(context).textTheme.headlineMedium),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20, color: AppTheme.accentColor),
                              onPressed: _showEditDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, color: AppTheme.warningColor, size: 20),
                            const SizedBox(width: 4),
                            Text('${user?.rating ?? 5.0} / 5.0', style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  _buildProfileSection(
                    context,
                    title: 'Primary Location',
                    icon: Icons.home,
                    value: user?.area ?? 'Not set',
                  ),
                  const Divider(),
                  _buildProfileSection(
                    context,
                    title: 'Contact',
                    icon: Icons.phone,
                    value: user?.phone ?? 'Not set',
                  ),
                  const Divider(),
                  _buildProfileSection(
                    context,
                    title: 'Email',
                    icon: Icons.email,
                    value: user?.email ?? '',
                    showEdit: false,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        // View history
                      },
                      child: const Text('View Full Job History'),
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildProfileSection(BuildContext context, {required String title, required IconData icon, required String value, bool showEdit = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
