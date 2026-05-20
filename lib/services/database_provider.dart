import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/appointment_model.dart';
import '../models/user_model.dart';
import '../core/constants.dart';

class DatabaseProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<AppointmentModel> _appointments = [];
  List<AppointmentModel> get appointments => _appointments;

  Future<void> fetchAppointments(UserModel user) async {
    _setLoading(true);
    try {
      final query = Supabase.instance.client
          .from('appointments')
          .select('*, provider:provider_id(name, profession), receiver:receiver_id(name)');

      if (user.role == UserRole.receiver) {
        query.eq('receiver_id', user.id);
      } else {
        query.eq('provider_id', user.id);
      }

      final response = await query.order('scheduled_at', ascending: true);
      _appointments = (response as List).map((e) => AppointmentModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Fetch Appointments Error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createAppointment(AppointmentModel appointment) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.from('appointments').insert(appointment.toJson());
    } catch (e) {
      debugPrint('Create Appointment Error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateAppointmentStatus(String id, AppointmentStatus status) async {
    try {
      await Supabase.instance.client
          .from('appointments')
          .update({'status': status.name})
          .eq('id', id);
      
      // Refresh local state by finding and updating
      final index = _appointments.indexWhere((a) => a.id == id);
      if (index != -1) {
        final old = _appointments[index];
        _appointments[index] = AppointmentModel(
          id: old.id,
          receiverId: old.receiverId,
          providerId: old.providerId,
          status: status,
          description: old.description,
          mediaUrl: old.mediaUrl,
          scheduledAt: old.scheduledAt,
          location: old.location,
          cost: old.cost,
          providerName: old.providerName,
          receiverName: old.receiverName,
          providerProfession: old.providerProfession,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Update Appointment Error: $e');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
