import '../core/json_parse.dart';
import 'role.dart';

/// Mirrors `AuthUser` in `src/App.tsx`.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.balance,
    this.status,
    this.region,
    this.lat,
    this.lng,
    this.phone,
    this.address,
    this.coverImage,
  });

  final String id;
  final String name;
  final String email;
  final AppRole role;
  final double balance;
  final String? status;
  final String? region;
  final double? lat;
  final double? lng;
  final String? phone;
  final String? address;
  final String? coverImage;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: AppRole.fromString(json['role']?.toString()),
      balance: parseJsonDoubleOrZero(json['balance']),
      status: json['status']?.toString(),
      region: json['region']?.toString(),
      lat: parseJsonDouble(json['lat']),
      lng: parseJsonDouble(json['lng']),
      phone: json['phone']?.toString(),
      address: json['address']?.toString(),
      coverImage: json['cover_image']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'balance': balance,
        if (status != null) 'status': status,
        if (region != null) 'region': region,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (coverImage != null) 'cover_image': coverImage,
      };

  AuthUser copyWith({
    String? name,
    double? balance,
    String? status,
    double? lat,
    double? lng,
    String? phone,
    String? address,
  }) {
    return AuthUser(
      id: id,
      name: name ?? this.name,
      email: email,
      role: role,
      balance: balance ?? this.balance,
      status: status ?? this.status,
      region: region,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      coverImage: coverImage,
    );
  }
}
