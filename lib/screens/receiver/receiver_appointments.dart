import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/database_provider.dart';
import '../../services/auth_provider.dart';
import '../../models/appointment_model.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class ReceiverAppointmentsScreen extends StatefulWidget {
  const ReceiverAppointmentsScreen({super.key});

  @override
  State<ReceiverAppointmentsScreen> createState() => _ReceiverAppointmentsScreenState();
}

class _ReceiverAppointmentsScreenState extends State<ReceiverAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
        context.read<DatabaseProvider>().fetchAppointments(user);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.accentColor,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Upcoming'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AppointmentList(status: AppointmentStatus.pending),
          _AppointmentList(status: AppointmentStatus.upcoming),
          _AppointmentList(status: AppointmentStatus.completed),
        ],
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  final AppointmentStatus status;

  const _AppointmentList({required this.status});

  @override
  Widget build(BuildContext context) {
    final appointments = context.watch<DatabaseProvider>().appointments
        .where((a) => a.status == status)
        .toList();

    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No bookings found', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.p16),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final job = appointments[index];
        return _AppointmentCard(job: job);
      },
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final AppointmentModel job;
  const _AppointmentCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final timeStr = job.scheduledAt != null ? DateFormat('MMM d, yyyy - h:mm a').format(job.scheduledAt!) : 'TBD';

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.p16),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.p16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(job.description ?? 'Service Request', style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(job.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    job.status.name.toUpperCase(),
                    style: TextStyle(color: _getStatusColor(job.status), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(timeStr, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            if (job.providerName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text('${job.providerName} (${job.providerProfession ?? "Professional"})', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (job.status == AppointmentStatus.pending || job.status == AppointmentStatus.upcoming) ...[
                  TextButton.icon(
                    onPressed: () {
                      context.read<DatabaseProvider>().updateAppointmentStatus(job.id, AppointmentStatus.cancelled);
                    },
                    icon: const Icon(Icons.cancel_outlined, color: AppTheme.errorColor),
                    label: const Text('Cancel', style: TextStyle(color: AppTheme.errorColor)),
                  ),
                ],
                if (job.status == AppointmentStatus.upcoming && job.providerName != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Call functionality
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return AppTheme.warningColor;
      case AppointmentStatus.upcoming:
        return AppTheme.accentColor;
      case AppointmentStatus.completed:
        return AppTheme.successColor;
      case AppointmentStatus.cancelled:
        return AppTheme.errorColor;
    }
  }
}
