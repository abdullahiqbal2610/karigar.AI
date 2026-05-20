import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../core/constants.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;



  Future<void> signIn(String email, String password) async {
    _setLoading(true);
    try {
      final AuthResponse response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
         await _fetchUserFromDB(response.user!.id, response.user!.email ?? '');
      }
    } catch (e) {
      debugPrint('Auth Error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    _setLoading(true);
    try {
      final AuthResponse response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );
      
      if (response.user != null) {
         await _fetchUserFromDB(response.user!.id, response.user!.email ?? '');
      }
    } catch (e) {
      debugPrint('Auth Error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _fetchUserFromDB(String id, String email) async {
    final response = await Supabase.instance.client
        .from('users')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response != null) {
      _currentUser = UserModel.fromJson(response);
    } else {
      // Create new user record
      final newUser = UserModel(
        id: id,
        email: email,
        role: UserRole.receiver, // Default role
      );
      await Supabase.instance.client.from('users').insert(newUser.toJson());
      _currentUser = newUser;
    }
  }

  Future<void> setRole(UserRole role) async {
    if (_currentUser == null) return;
    
    _setLoading(true);
    try {
      await Supabase.instance.client
          .from('users')
          .update({'role': role.name})
          .eq('id', _currentUser!.id);
      _currentUser = _currentUser!.copyWith(
        name: _currentUser!.name, // dummy copy to update role since copyWith doesn't have role currently, let's just create a new one
      );
      _currentUser = UserModel(
          id: _currentUser!.id,
          email: _currentUser!.email,
          role: role,
          name: _currentUser!.name,
          phone: _currentUser!.phone,
          area: _currentUser!.area,
          rating: _currentUser!.rating,
          profession: _currentUser!.profession,
          availability: _currentUser!.availability,
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateProfile(Map<String, dynamic> updates) async {
    if (_currentUser == null) return;
    _setLoading(true);
    try {
      await Supabase.instance.client
          .from('users')
          .update(updates)
          .eq('id', _currentUser!.id);
          
      // Refresh user from DB
      await _fetchUserFromDB(_currentUser!.id, _currentUser!.email);
    } catch (e) {
      debugPrint('Profile Update Error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.signOut();
      _currentUser = null;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
