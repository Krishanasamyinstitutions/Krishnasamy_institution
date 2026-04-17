/// Institution user (staff/admin) model matching Supabase 'institutionusers' table
class InstitutionUserModel {
  final int useId;
  final int? insId;
  final String inscode;
  final String usename;
  final String usemail;
  final String usephone;
  final String? usepassword;
  final DateTime usestadate;
  final int useotpstatus;
  final DateTime usedob;
  final String? usecategory;
  final int urId;
  final String urname;
  final int desId;
  final String desname;
  final int userepto;
  final int activestatus;

  InstitutionUserModel({
    required this.useId,
    this.insId,
    required this.inscode,
    required this.usename,
    required this.usemail,
    required this.usephone,
    this.usepassword,
    required this.usestadate,
    this.useotpstatus = 0,
    required this.usedob,
    this.usecategory,
    required this.urId,
    required this.urname,
    required this.desId,
    required this.desname,
    required this.userepto,
    this.activestatus = 1,
  });

  factory InstitutionUserModel.fromJson(Map<String, dynamic> json) {
    return InstitutionUserModel(
      useId: json['use_id'] is int
          ? json['use_id']
          : int.parse(json['use_id'].toString()),
      insId: json['ins_id'] != null
          ? (json['ins_id'] is int
              ? json['ins_id']
              : int.parse(json['ins_id'].toString()))
          : null,
      inscode: json['inscode'] ?? '',
      usename: json['usename'] ?? '',
      usemail: json['usemail'] ?? '',
      usephone: json['usephone']?.toString() ?? '',
      usepassword: json['usepassword'],
      usestadate: json['usestadate'] != null
          ? DateTime.parse(json['usestadate'])
          : DateTime.now(),
      useotpstatus: json['useotpstatus'] ?? 0,
      usedob: json['usedob'] != null
          ? DateTime.parse(json['usedob'])
          : DateTime.now(),
      usecategory: json['usecategory'],
      urId: json['ur_id'] != null
          ? (json['ur_id'] is int ? json['ur_id'] : int.parse(json['ur_id'].toString()))
          : 0,
      urname: json['urname'] ?? '',
      desId: json['des_id'] != null
          ? (json['des_id'] is int ? json['des_id'] : int.parse(json['des_id'].toString()))
          : 0,
      desname: json['desname'] ?? '',
      userepto: json['userepto'] != null
          ? (json['userepto'] is int ? json['userepto'] : int.parse(json['userepto'].toString()))
          : 0,
      activestatus: json['activestatus'] ?? 1,
    );
  }

  String get name => usename;
  String get email => usemail;
  String get phone => usephone;
  String get role => urname;
  String get designation => desname;
  bool get isActive => activestatus == 1;
}
