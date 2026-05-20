import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/database_provider.dart';
import '../../models/appointment_model.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class ProviderAppointmentsScreen extends StatefulWidget {
  const ProviderAppointmentsScreen({super.key});

  @override
  State<ProviderAppointmentsScreen> createState() => _ProviderAppointmentsScreenState();
}

class _ProviderAppointmentsScreenState extends State<ProviderAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: const Text('Appointments'),
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
            Text('No appointments found', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey.shade500)),
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

class _AppointmentCard extends StatefulWidget {
  final AppointmentModel job;
  const _AppointmentCard({required this.job});

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final timeStr = widget.job.scheduledAt != null ? DateFormat('MMM d, yyyy - h:mm a').format(widget.job.scheduledAt!) : 'TBD';

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.p16),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(widget.job.description ?? 'Job Request', style: Theme.of(context).textTheme.titleLarge),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(timeStr, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.person, 'Client', widget.job.receiverName ?? 'Unknown User'),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.location_on, 'Location', widget.job.location ?? 'Not provided'),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.attach_money, 'Estimated Cost', '\$${widget.job.cost?.toStringAsFixed(2) ?? 'TBD'}'),
                  
                  const SizedBox(height: 24),
                  if (widget.job.status == AppointmentStatus.pending)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              context.read<DatabaseProvider>().updateAppointmentStatus(widget.job.id, AppointmentStatus.cancelled);
                            },
                            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: const BorderSide(color: AppTheme.errorColor)),
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              context.read<DatabaseProvider>().updateAppointmentStatus(widget.job.id, AppointmentStatus.upcoming);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  
                  if (widget.job.status == AppointmentStatus.upcoming)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          context.read<DatabaseProvider>().updateAppointmentStatus(widget.job.id, AppointmentStatus.completed);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor),
                        child: const Text('Mark as Completed'),
                      ),
                    ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }
}
