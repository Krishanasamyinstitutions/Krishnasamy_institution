/// Fee demand model matching Supabase 'feedemand' table
class FeeModel {
  final int demId;
  final String demno;
  final int insId;
  final String inscode;
  final int yrId;
  final String demseqtype;
  final int? stuId;
  final String stuadmno;
  final String stuclass;
  final String demfeeyear;
  final String demfeeterm;
  final String demfeetype;
  final String? demfeecategory;
  final double feeamount;
  final int? conId;
  final double conamount;
  final double paidamount;
  final double balancedue;
  final int? payId;
  final String paidstatus;
  final String createdby;
  final DateTime createdat;
  final int activestatus;
  final DateTime? duedate;

  FeeModel({
    required this.demId,
    required this.demno,
    required this.insId,
    required this.inscode,
    required this.yrId,
    required this.demseqtype,
    this.stuId,
    required this.stuadmno,
    required this.stuclass,
    required this.demfeeyear,
    required this.demfeeterm,
    required this.demfeetype,
    this.demfeecategory,
    required this.feeamount,
    this.conId,
    this.conamount = 0,
    this.paidamount = 0,
    required this.balancedue,
    this.payId,
    required this.paidstatus,
    required this.createdby,
    required this.createdat,
    this.activestatus = 1,
    this.duedate,
  });

  factory FeeModel.fromJson(Map<String, dynamic> json) {
    return FeeModel(
      demId: json['dem_id'] is int
          ? json['dem_id']
          : int.parse(json['dem_id'].toString()),
      demno: json['demno'] ?? '',
      insId: json['ins_id'] is int
          ? json['ins_id']
          : int.parse(json['ins_id'].toString()),
      inscode: json['inscode'] ?? '',
      yrId: json['yr_id'] is int
          ? json['yr_id']
          : int.parse(json['yr_id'].toString()),
      demseqtype: json['demseqtype'] ?? '',
      stuId: json['stu_id'] != null
          ? (json['stu_id'] is int
              ? json['stu_id']
              : int.parse(json['stu_id'].toString()))
          : null,
      stuadmno: json['stuadmno'] ?? '',
      stuclass: json['stuclass'] ?? '',
      demfeeyear: json['demfeeyear'] ?? '',
      demfeeterm: json['demfeeterm'] ?? '',
      demfeetype: json['demfeetype'] ?? '',
      demfeecategory: json['demfeecategory'],
      feeamount: (json['feeamount'] as num?)?.toDouble() ?? 0,
      conId: json['con_id'] != null
          ? (json['con_id'] is int
              ? json['con_id']
              : int.parse(json['con_id'].toString()))
          : null,
      conamount: (json['conamount'] as num?)?.toDouble() ?? 0,
      paidamount: (json['paidamount'] as num?)?.toDouble() ?? 0,
      balancedue: (json['balancedue'] as num?)?.toDouble() ?? 0,
      payId: json['pay_id'] != null
          ? (json['pay_id'] is int
              ? json['pay_id']
              : int.parse(json['pay_id'].toString()))
          : null,
      paidstatus: json['paidstatus'] ?? 'U',
      createdby: json['createdby'] ?? '',
      createdat: json['createdat'] != null
          ? DateTime.parse(json['createdat'])
          : DateTime.now(),
      activestatus: json['activestatus'] ?? 1,
      duedate:
          json['duedate'] != null ? DateTime.parse(json['duedate']) : null,
    );
  }

  bool get isPaid => paidstatus == 'P';
  double get totalAmount => feeamount - conamount;
}

/// Fee summary for dashboard display
class FeeSummary {
  final double totalDue;
  final double totalPaid;
  final double totalPending;
  final int pendingCount;

  FeeSummary({
    required this.totalDue,
    required this.totalPaid,
    required this.totalPending,
    required this.pendingCount,
  });
}
