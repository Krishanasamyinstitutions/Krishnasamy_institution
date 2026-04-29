# Bank Reconciliation Test Data

Three sample bank statements (HDFC, ICICI, SBI) and the matching app-side payments to enter so the reconciliation flow can be exercised end-to-end.

## How to use

1. In Fee Collection, record the cheque + UPI payments listed below for any students you have. The numbers in **Cheque No.** / **UTR/Ref** must match exactly.
2. Open Bank Reconciliation, upload one of the three CSVs in this folder.
3. The matched rows should auto-link by amount + reference; the unmatched rows (cash withdrawals, POS, etc.) stay un-reconciled.

---

## Cheque payments to record

| Bank   | Cheque No. | Amount  | Date       |
|--------|------------|---------|------------|
| HDFC   | 100234     | 8,500   | 02/04/2026 |
| HDFC   | 100235     | 15,000  | 05/04/2026 |
| ICICI  | 200145     | 11,000  | 09/04/2026 |
| ICICI  | 200146     | 18,500  | 12/04/2026 |
| SBI    | 300456     | 9,500   | 14/04/2026 |
| SBI    | 300457     | 13,500  | 16/04/2026 |
| SBI    | 300458     | 22,000  | 19/04/2026 |
| IOB    | 400123     | 12,500  | 20/04/2026 |
| IOB    | 400124     | 16,800  | 23/04/2026 |
| IOB    | 400125     | 9,500   | 24/04/2026 |

## UPI / QR / NEFT / IMPS payments to record

Use the **UTR / Ref No.** below as the payment reference (the app's `payreference` / `payorderid`).

| Bank   | Mode | UTR / Ref No.   | Amount  | Date       |
|--------|------|-----------------|---------|------------|
| HDFC   | UPI  | 426001234567    | 5,500   | 01/04/2026 |
| HDFC   | NEFT | HDFCN26010001   | 12,500  | 02/04/2026 |
| HDFC   | UPI  | 426134567890    | 3,200   | 03/04/2026 |
| HDFC   | IMPS | 426211223344    | 7,800   | 04/04/2026 |
| HDFC   | UPI  | 426355667788    | 4,500   | 07/04/2026 |
| ICICI  | UPI  | IB456789012345  | 6,300   | 08/04/2026 |
| ICICI  | UPI  | IB456891011121  | 2,750   | 09/04/2026 |
| ICICI  | NEFT | ICICN26100002   | 9,800   | 10/04/2026 |
| ICICI  | IMPS | 457012345678    | 5,200   | 11/04/2026 |
| ICICI  | UPI  | IB458123456789  | 3,850   | 13/04/2026 |
| SBI    | UPI  | 498012345001    | 4,100   | 14/04/2026 |
| SBI    | UPI  | 498123456002    | 2,900   | 15/04/2026 |
| SBI    | NEFT | SBIN26160003    | 7,200   | 16/04/2026 |
| SBI    | IMPS | 498234567003    | 5,650   | 17/04/2026 |
| SBI    | UPI  | 498345678004    | 3,300   | 18/04/2026 |
| IOB    | UPI  | IOB512345001    | 3,450   | 20/04/2026 |
| IOB    | UPI  | IOB512345002    | 2,200   | 21/04/2026 |
| IOB    | NEFT | IOBN26210001    | 8,900   | 21/04/2026 |
| IOB    | IMPS | IOB512345003    | 4,750   | 22/04/2026 |
| IOB    | UPI  | IOB512345004    | 3,100   | 23/04/2026 |

## Files

- `HDFC_bank_statement.csv` — HDFC layout: `Date | Narration | Chq/Ref No | Value Date | Withdrawal Amt | Deposit Amt | Closing Balance`
- `ICICI_bank_statement.csv` — ICICI layout: `S.No. | Value Date | Transaction Date | Cheque Number | Transaction Remarks | Withdrawal Amount (INR) | Deposit Amount (INR) | Balance (INR)`
- `SBI_bank_statement.csv` — SBI layout: `Txn Date | Value Date | Description | Ref No./Cheque No. | Debit | Credit | Balance`
- `IOB_bank_statement.csv` — IOB layout: `Sr.No. | Date | Particulars | Inst. No | Withdrawal (Dr) | Deposit (Cr) | Balance`

Each statement also contains 1–2 noise rows (ATM withdrawals, POS) that are debits and should be skipped by the parser, so you can confirm filtering works.
