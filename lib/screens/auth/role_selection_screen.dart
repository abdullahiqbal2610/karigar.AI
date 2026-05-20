import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_provider.dart';
import '../../models/user_model.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Role'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.p24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How would you like to use Karigar?',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.p32),
              _buildRoleCard(
                context,
                title: 'Service Provider',
                subtitle: 'Find jobs and manage your appointments',
                icon: Icons.work_outline,
                role: UserRole.provider,
              ),
              const SizedBox(height: AppConstants.p16),
              _buildRoleCard(
                context,
                title: 'Service Receiver',
                subtitle: 'Book professionals for your needs',
                icon: Icons.search,
                role: UserRole.receiver,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required UserRole role,
  }) {
    return InkWell(
      onTap: () async {
        await context.read<AuthProvider>().setRole(role);
        if (context.mounted) {
          context.go('/dashboard');
        }
      },
      borderRadius: BorderRadius.circular(AppConstants.r16),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.p24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.r16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.accentColor, size: 32),
            ),
            const SizedBox(width: AppConstants.p24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
