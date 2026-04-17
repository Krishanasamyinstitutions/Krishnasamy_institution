/// Institution model matching Supabase 'institution' table
class InstitutionModel {
  final int insId;
  final String inscode;
  final String insname;
  final String? insaddress1;
  final String? insaddress2;
  final String? insaddress3;
  final String? cityName;
  final String? inspincode;
  final String? insmobno;
  final String? insmail;
  final int activestatus;

  InstitutionModel({
    required this.insId,
    required this.inscode,
    required this.insname,
    this.insaddress1,
    this.insaddress2,
    this.insaddress3,
    this.cityName,
    this.inspincode,
    this.insmobno,
    this.insmail,
    this.activestatus = 1,
  });

  factory InstitutionModel.fromJson(Map<String, dynamic> json) {
    String? cityName;
    if (json['city'] != null && json['city'] is Map) {
      cityName = json['city']['citname'];
    }

    return InstitutionModel(
      insId: json['ins_id'] is int
          ? json['ins_id']
          : int.parse(json['ins_id'].toString()),
      inscode: json['inscode'] ?? '',
      insname: json['insname'] ?? '',
      insaddress1: json['insaddress1'],
      insaddress2: json['insaddress2'],
      insaddress3: json['insaddress3'],
      cityName: cityName,
      inspincode: json['inspincode'],
      insmobno: json['insmobno'],
      insmail: json['insmail'],
      activestatus: json['activestatus'] ?? 1,
    );
  }

  String get name => insname;
  String get code => inscode;
  bool get isActive => activestatus == 1;

  String get fullAddress {
    final parts = [insaddress1, insaddress2, insaddress3, cityName, inspincode]
        .where((p) => p != null && p.isNotEmpty)
        .toList();
    return parts.isNotEmpty ? parts.join(', ') : 'Address not available';
  }
}
