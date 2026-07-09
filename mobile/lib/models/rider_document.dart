/// Driver KYC document (licence, Ghana card, profile photo).
class RiderDocument {
  const RiderDocument({
    required this.docType,
    required this.imageUrl,
    this.reviewStatus,
    this.rejectionReason,
    this.uploadedAt,
  });

  final String docType;
  final String imageUrl;
  final String? reviewStatus;
  final String? rejectionReason;
  final String? uploadedAt;

  factory RiderDocument.fromJson(Map<String, dynamic> json) {
    return RiderDocument(
      docType: json['doc_type']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      reviewStatus: json['review_status']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      uploadedAt: json['uploaded_at']?.toString(),
    );
  }
}

class RiderDocumentsState {
  const RiderDocumentsState({
    required this.documents,
    this.status,
    this.complete = false,
    this.readyForReview = false,
  });

  final List<RiderDocument> documents;
  final String? status;
  final bool complete;
  final bool readyForReview;

  factory RiderDocumentsState.fromJson(Map<String, dynamic> json) {
    final raw = json['documents'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => RiderDocument.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <RiderDocument>[];
    return RiderDocumentsState(
      documents: list,
      status: json['status']?.toString(),
      complete: json['complete'] == true,
      readyForReview: json['ready_for_review'] == true,
    );
  }
}

/// Rider application for admin review.
class PendingRiderApplication {
  const PendingRiderApplication({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.region,
    this.status,
    this.riderVehicleType,
    required this.documents,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? region;
  final String? status;
  final String? riderVehicleType;
  final List<RiderDocument> documents;

  factory PendingRiderApplication.fromJson(Map<String, dynamic> json) {
    final raw = json['documents'];
    List<RiderDocument> docs = [];
    if (raw is List) {
      docs = raw
          .whereType<Map>()
          .map((e) => RiderDocument.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return PendingRiderApplication(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      region: json['region']?.toString(),
      status: json['status']?.toString(),
      riderVehicleType: json['rider_vehicle_type']?.toString(),
      documents: docs,
    );
  }
}
