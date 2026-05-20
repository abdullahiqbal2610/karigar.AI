import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/database_provider.dart';
import '../../services/auth_provider.dart';
import '../../models/appointment_model.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class ProviderDashboard extends StatefulWidget {
  const ProviderDashboard({super.key});

  @override
  State<ProviderDashboard> createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends State<ProviderDashboard> {
  String _filter = '3 Days'; // '3 Days' or '1 Week'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
        context.read<DatabaseProvider>().fetchAppointments(user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dbProvider = context.watch<DatabaseProvider>();
    final upcomingAppointments = dbProvider.appointments
        .where((a) => a.status == AppointmentStatus.upcoming)
        .toList();



    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            final user = context.read<AuthProvider>().currentUser;
            if (user != null) {
              await context.read<DatabaseProvider>().fetchAppointments(user);
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppConstants.p16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: AppConstants.p24),
                _buildFilterToggle(),
                const SizedBox(height: AppConstants.p16),
                _buildUpcomingJobsList(upcomingAppointments),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello, ${user?.name ?? "Provider"}!', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 4),
            Text('Here is your schedule.', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        CircleAvatar(
          backgroundColor: AppTheme.accentColor.withOpacity(0.1),
          radius: 24,
          child: const Icon(Icons.person, color: AppTheme.accentColor),
        ),
      ],
    );
  }

  Widget _buildFilterToggle() {
    return Row(
      children: [
        _buildFilterChip('3 Days'),
        const SizedBox(width: AppConstants.p8),
        _buildFilterChip('1 Week'),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _filter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _filter = label);
      },
      selectedColor: AppTheme.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppTheme.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildUpcomingJobsList(List<AppointmentModel> appointments) {
    if (appointments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No upcoming jobs in this period.')),
      );
    }
    
    // Simple filter logic mock
    final limit = _filter == '3 Days' ? 3 : 7;
    final now = DateTime.now();
    final filtered = appointments.where((a) {
      if (a.scheduledAt == null) return false;
      return a.scheduledAt!.isBefore(now.add(Duration(days: limit)));
    }).toList();

    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No upcoming jobs in this period.')),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppConstants.p16),
      itemBuilder: (context, index) {
        final job = filtered[index];
        final timeStr = job.scheduledAt != null ? DateFormat('MMM d, h:mm a').format(job.scheduledAt!) : 'TBD';
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.p16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.build, color: AppTheme.accentColor),
                ),
                const SizedBox(width: AppConstants.p16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.description ?? 'Job Request', style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(timeStr, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.accentColor)),
                      const SizedBox(height: 4),
                      Text(job.location ?? 'No location provided', style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


}
