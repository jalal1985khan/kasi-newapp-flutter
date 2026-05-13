class WebsiteResource {
  final String id;
  final String tenantId;
  final String name;
  final String url;
  final int sNo;
  final bool isActive;
  final DateTime createdAt;

  WebsiteResource({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.url,
    required this.sNo,
    required this.isActive,
    required this.createdAt,
  });

  factory WebsiteResource.fromJson(Map<String, dynamic> json) {
    return WebsiteResource(
      id: json['_id'] ?? '',
      tenantId: json['tenantId'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      sNo: json['sNo'] ?? 0,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'sNo': sNo,
      'isActive': isActive,
    };
  }
}
