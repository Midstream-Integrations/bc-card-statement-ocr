# BC ⇄ OCR server contract

The Business Central extension talks to an OCR and receipts-portal server over HTTPS. Use this page to self-host, replace or extend the server.

## Business Central → server

Every call goes to `https://<OCR Host><path>` with header `X-API-Key: <OCR API Key>`. Errors should return a non-2xx status and a JSON body like `{"detail": "message"}`; BC shows `detail` to the user.

| Method and path | Body | Returns | Used by |
|---|---|---|---|
| `GET /api/merchants` | none | `[{"id": "huntington", "label": "Huntington Business Card"}, {"id": "usbank", "label": "U.S. Bank Business Card"}]` | Test OCR Connection |
| `POST /api/statements?merchant=<id or auto>&filename=<name>` | the statement PDF (`application/pdf`) | `{"statementId", "closingDate", "cardholders": [{"label", "name", "last4"}]}` | Card Statement OCR |
| `POST /api/assignments` | `{"statementId", "last4", "invoiceId", "invoiceNo", "companyId", "managerEmail", "managerName", "senderEmail"}` | `{"url", "token"}`; BC sends the link. `senderEmail` (optional) is emailed when the manager approves | Card Statement OCR |
| `POST /api/reqapproval/send` | `{"invoiceId", "invoiceNo", "companyId", "vendorNo", "vendorName", "vendorInvoiceNo", "attachmentId", "attachmentName", "managerEmail", "managerName", "creatorEmail"}` | any 2xx; the server emails the manager | Send for Requisition Approval |
| `POST /api/reqform/stamp` | `{"pdfBase64", "cost", "glAccount", "signedBy", "signedAt"}` | `{"pdfBase64"}`: the stamped form | After a submission is processed |

- `invoiceId`, `companyId` and `attachmentId` are BC SystemIds (GUIDs without braces).
- `cardholders[].label` is shown in a selection menu, so it must not contain commas.
- `merchant` ids must match the **MID Card Merchant** enum (see `MerchantId()` in `CardStmtMgt.Codeunit.al`).
- `signedAt` is ISO 8601 UTC; `glAccount` is the shared `account-dim1-dim2` string, or `MULTIPLE`.
- Calls can take up to 5 minutes (BC's timeout is 300 seconds), so OCR of a scanned statement can run synchronously.

## Server → Business Central

The server signs in as a Microsoft Entra application (client credentials) that's registered on BC's **Microsoft Entra Applications** page with the `MID OCR USER` and `D365 PURCH DOC, EDIT` permission sets.

There are two ways to write a submission back:

- **Directly through the standard API (what [bc-card-statement-ocr-server](https://github.com/Midstream-Integrations/bc-card-statement-ocr-server) does).** The server adds `purchaseInvoiceLines` and their `dimensionSetLines`, uploads receipts as `documentAttachments`, stamps the `RequisitionForm-<invoice no.>` attachment itself and uploads it as `RequisitionForm-<invoice no.>-signed.pdf`, then sets `mgrRequisitionApproval` to `APPROVED` through the requisition approval API below. `/api/reqform/stamp` is not needed in this mode.
- **Through the card statement API in this extension**, below. BC creates the lines in one transaction and calls `/api/reqform/stamp` on your server to sign the form. This is the simpler option if you write your own server.

Card statement API base URL:

```
https://api.businesscentral.dynamics.com/v2.0/<tenant>/<environment>/api/midstream/cardStatement/v1.0/companies(<companyId>)
```

When a manager submits:

1. `POST /cardStatementBatches` with `{"invoiceId", "assignmentToken", "submittedBy", "cardholder", "submittedAt"}`. Read `id` from the response.
2. `POST /cardStatementLines` once per transaction:
   `{"batchId", "lineNo", "transactionDate", "description", "reference", "amount", "glAccountNo", "dimension1Code", "dimension2Code", "receiptFileName", "receiptBase64", "receiptCheck", "receiptNote"}`
   - `amount`: purchases positive, credits negative.
   - `receiptCheck`: `match`, `found`, `missing`, `date_mismatch`, any other value (shown as a mismatch), or empty for credits.
3. `POST /cardStatementBatches(<id>)/Microsoft.NAV.process`. In one transaction, this creates the invoice lines, attaches the receipts, comments on problems, marks the requisition approved and calls `/api/reqform/stamp`.

Lines can only be added to a batch that's still `Pending`, and a token can only be processed once.

Requisition approval status lives on the purchase invoice and can be read or updated through:

```
.../api/midstream/RequisitionApprovalInvoices/v1.0/companies(<companyId>)/RequisitionApprovalInvoices
```

Fields include `mgrRequisitionApproval`, `HigherRequisitionApproval`, `HigherRequisitionEmail`, `HigherRequisitionName`, `RequisitionCreatorName` and `RequisitionCreatorEmail`.
