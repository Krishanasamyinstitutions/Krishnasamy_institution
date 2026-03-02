/// Payment model matching Supabase 'payment' table
class PaymentModel {
  final int payId;
  final int insId;
  final String? inscode;
  final int? stuId;
  final int yrId;
  final String? yrlabel;
  final double transtotalamount;
  final String transcurrency;
  final DateTime? paydate;
  final String? paystatus;
  final String? paymethod;
  final String? payreference;
  final String? createdby;
  final DateTime createdat;
  final int activestatus;

  PaymentModel({
    required this.payId,
    required this.insId,
    this.inscode,
    this.stuId,
    required this.yrId,
    this.yrlabel,
    this.transtotalamount = 0,
    this.transcurrency = 'INR',
    this.paydate,
    this.paystatus,
    this.paymethod,
    this.payreference,
    this.createdby,
    required this.createdat,
    this.activestatus = 1,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      payId: json['pay_id'] is int
          ? json['pay_id']
          : int.parse(json['pay_id'].toString()),
      insId: json['ins_id'] is int
          ? json['ins_id']
          : int.parse(json['ins_id'].toString()),
      inscode: json['inscode'],
      stuId: json['stu_id'] != null
          ? (json['stu_id'] is int
              ? json['stu_id']
              : int.parse(json['stu_id'].toString()))
          : null,
      yrId: json['yr_id'] is int
          ? json['yr_id']
          : int.parse(json['yr_id'].toString()),
      yrlabel: json['yrlabel'],
      transtotalamount:
          (json['transtotalamount'] as num?)?.toDouble() ?? 0,
      transcurrency: json['transcurrency'] ?? 'INR',
      paydate:
          json['paydate'] != null ? DateTime.parse(json['paydate']) : null,
      paystatus: json['paystatus'],
      paymethod: json['paymethod'],
      payreference: json['payreference'],
      createdby: json['createdby'],
      createdat: json['createdat'] != null
          ? DateTime.parse(json['createdat'])
          : DateTime.now(),
      activestatus: json['activestatus'] ?? 1,
    );
  }

  double get amount => transtotalamount;
  bool get isSuccess => paystatus == 'C';

  String get statusText {
    switch (paystatus) {
      case 'C':
        return 'Completed';
      case 'F':
        return 'Failed';
      case 'R':
        return 'Refunded';
      case 'I':
        return 'Initiated';
      default:
        return 'Pending';
    }
  }
}
