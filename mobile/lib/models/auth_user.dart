import '../core/json_parse.dart';
import '../shared/client_image_url.dart';
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
    this.isOnline,
    this.region,
    this.lat,
    this.lng,
    this.phone,
    this.address,
    this.coverImage,
    this.avatarUrl,
    this.hasAvatar = false,
    this.shopCategory,
  });

  final String id;
  final String name;
  final String email;
  final AppRole role;
  final double balance;
  final String? status;
  final bool? isOnline;
  final String? region;
  final double? lat;
  final double? lng;
  final String? phone;
  final String? address;
  final String? coverImage;
  final String? avatarUrl;
  final bool hasAvatar;
  final String? shopCategory;

  static String? _persistImageField(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:')) return null;
    return url;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: AppRole.fromString(json['role']?.toString()),
      balance: parseJsonDoubleOrZero(json['balance']),
      status: json['status']?.toString(),
      isOnline: json['is_online'] == true,
      region: json['region']?.toString(),
      lat: parseJsonDouble(json['lat']),
      lng: parseJsonDouble(json['lng']),
      phone: json['phone']?.toString(),
      address: json['address']?.toString(),
      coverImage: ClientImageUrl.resolve(json['cover_image']?.toString()),
      avatarUrl: ClientImageUrl.resolve(json['avatar_url']?.toString()),
      hasAvatar: json['has_avatar'] == true,
      shopCategory: json['shop_category']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'balance': balance,
        if (status != null) 'status': status,
        if (isOnline != null) 'is_online': isOnline,
        if (region != null) 'region': region,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (coverImage != null) 'cover_image': _persistImageField(coverImage),
        if (avatarUrl != null) 'avatar_url': _persistImageField(avatarUrl),
        if (hasAvatar) 'has_avatar': hasAvatar,
        if (shopCategory != null) 'shop_category': shopCategory,
      };

  AuthUser copyWith({
    String? name,
    double? balance,
    String? status,
    bool? isOnline,
    double? lat,
    double? lng,
    String? phone,
    String? address,
    String? avatarUrl,
    bool? hasAvatar,
    String? coverImage,
  }) {
    return AuthUser(
      id: id,
      name: name ?? this.name,
      email: email,
      role: role,
      balance: balance ?? this.balance,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      region: region,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      coverImage: coverImage ?? this.coverImage,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      shopCategory: shopCategory,
    );
  }
}
