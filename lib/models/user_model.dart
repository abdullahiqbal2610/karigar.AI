enum UserRole { provider, receiver }

class UserModel {
  final String id;
  final String email;
  final UserRole role;
  final String? name;
  final String? phone;
  final String? area;
  final double rating;
  final String? profession;
  final Map<String, dynamic>? availability;

  UserModel({
    required this.id,
    required this.email,
    required this.role,
    this.name,
    this.phone,
    this.area,
    this.rating = 0.0,
    this.profession,
    this.availability,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      role: json['role'] == 'provider' ? UserRole.provider : UserRole.receiver,
      name: json['name'],
      phone: json['phone'],
      area: json['area'],
      rating: (json['rating'] ?? 0).toDouble(),
      profession: json['profession'],
      availability: json['availability'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role.name,
      'name': name,
      'phone': phone,
      'area': area,
      'rating': rating,
      'profession': profession,
      'availability': availability,
    };
  }

  // Copy with method for state updates
  UserModel copyWith({
    String? name,
    String? phone,
    String? area,
    String? profession,
    Map<String, dynamic>? availability,
  }) {
    return UserModel(
      id: id,
      email: email,
      role: role,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      area: area ?? this.area,
      rating: rating,
      profession: profession ?? this.profession,
      availability: availability ?? this.availability,
    );
  }
}
