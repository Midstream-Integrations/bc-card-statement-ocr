# Changelog

All notable changes to this project are listed here. Versions follow the `app.json` version.

## [1.0.3.0] - Unreleased

First public release.

- **Card Statement OCR** from a purchase invoice: upload the statement PDF, pick the cardholder and approving manager (and optionally a 2nd approver), and BC emails the manager a portal link. Every statement is sent as **Credit Card Merchant**; the OCR server recognizes the issuer from the PDF.
- **Send for Requisition Approval** for vendor invoices, with an optional 2nd approver.
- The sender's email is passed to the OCR server, which emails them when the manager approves.
- Report 50120 **MID Requisition Form**: a generic one-page requisition form the OCR server can sign. Or use your own report.
- API pages for the OCR server: `RequisitionApprovalInvoices` and the `cardStatement` batch API (see [docs/API.md](docs/API.md)).
