enum AppointmentStatus { pending, upcoming, completed, cancelled }

class AppointmentModel {
  final String id;
  final String receiverId;
  final String? providerId;
  final AppointmentStatus status;
  final String? description;
  final String? mediaUrl;
  final DateTime? scheduledAt;
  final String? location;
  final double? cost;

  // Additional fields for UI display (joined from users table)
  final String? providerName;
  final String? receiverName;
  final String? providerProfession;

  AppointmentModel({
    required this.id,
    required this.receiverId,
    this.providerId,
    this.status = AppointmentStatus.pending,
    this.description,
    this.mediaUrl,
    this.scheduledAt,
    this.location,
    this.cost,
    this.providerName,
    this.receiverName,
    this.providerProfession,
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id'],
      receiverId: json['receiver_id'],
      providerId: json['provider_id'],
      status: AppointmentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AppointmentStatus.pending,
      ),
      description: json['description'],
      mediaUrl: json['media_url'],
      scheduledAt: json['scheduled_at'] != null ? DateTime.parse(json['scheduled_at']) : null,
      location: json['location'],
      cost: json['cost'] != null ? (json['cost'] as num).toDouble() : null,
      
      // Attempt to read nested user data if joined
      providerName: json['provider']?['name'],
      providerProfession: json['provider']?['profession'],
      receiverName: json['receiver']?['name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'receiver_id': receiverId,
      'provider_id': providerId,
      'status': status.name,
      'description': description,
      'media_url': mediaUrl,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'location': location,
      'cost': cost,
    };
  }
}
