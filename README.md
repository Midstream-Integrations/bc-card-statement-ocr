# Card Statement OCR and Requisition Approval for Business Central

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg) ![Business Central 25+](https://img.shields.io/badge/Business%20Central-25%2B-0B7E8A) ![AL](https://img.shields.io/badge/language-AL-5C2D91)

**Turn a company credit card statement into a coded, receipted purchase invoice, and route vendor invoices for manager approval from an email link.**

<!-- DEMO: record a 30-60 second screen capture, save it as docs/images/demo.gif, then replace this comment with:
![Demo](docs/images/demo.gif) -->

## Why

Card statements are where accounts payable time disappears. Someone chases every cardholder for receipts, someone else types every charge into Business Central, and the G/L coding is a best guess. The people who know what each charge was for (managers and cardholders) usually don't work in BC at all.

## What it does

- **Card Statement OCR.** From a purchase invoice, upload the statement PDF. The OCR server reads it and lists the cardholders on it. Pick one and the approving manager.
- **Receipts portal.** The manager gets an email link to a web portal. For each charge they upload the receipt and enter the G/L account and your shortcut dimension codes, then press Submit. They sign in with their Microsoft 365 account; no BC license is needed.
- **Invoice lines, built for you.** BC creates one purchase line per charge, attaches each receipt, adds a comment where a receipt doesn't match the amount or a G/L or dimension code isn't valid, and marks the requisition approved.
- **Signed requisition form.** A requisition form (the included report 50120, or your own) is attached, then stamped with the total, G/L account and approver when the manager submits.
- **Requisition approval for vendor invoices.** Pick a manager and an optional second approver, upload the vendor invoice, and the approval request goes out by email. If anything fails, everything that was saved is rolled back. Whoever sent it gets an email once it's approved.
- **Audit trail.** Every request, who it went to and when it was submitted is kept on the **Card Statement Requests** page.

## How it works

```
Purchase Invoice ──upload statement──▶ OCR server ──parses──▶ cardholders
        ▲                                   │
        │                                   ├─ emails manager a portal link
        │                                   ▼
  invoice lines + receipts ◀── BC API ◀── manager submits receipts + coding
```

The BC extension in this repo is one half. The other half is the **OCR and portal server**, [bc-card-statement-ocr-server](https://github.com/Midstream-Integrations/bc-card-statement-ocr-server), which you can self-host on a Linux server or have [hosted by Midstream Integrations](https://www.MidstreamIntegrations.com). The full install guide for both halves is [here](https://github.com/Midstream-Integrations/bc-card-statement-ocr-server/blob/main/docs/INSTALL.md). The contract between the two is documented in [docs/API.md](docs/API.md), so you can also build your own server.

## Setup

1. **Endpoint API Setup** page:
   - **OCR Host**: your server's host name, for example `ocr.example.com`.
   - **OCR API Key**: the shared key the server expects. It's stored in isolated storage, never in a table.
   - **Requisition Form Report ID**: `50120` (**MID Requisition Form**, included), or your own report that prints the labels the server signs (see the server's install guide, section 11.3).
   - Use **Test OCR Connection** to check it.
2. **Requisition Managers** page: add each approver's name and email.
3. In Microsoft Entra ID, register an app for the server and add it to BC's **Microsoft Entra Applications** page with the `MID OCR USER` and `D365 PURCH DOC, EDIT` permission sets, so the server can post submissions back.
4. Assign `MID OCR USER` to AP users and `MID ENDPOINT SETUP` to admins.
5. **Email Accounts**: set a default account. BC sends the card statement email to the manager through it. Use the **Microsoft 365** or **Current User** connector, or **SMTP** with **OAuth 2.0**. SMTP with a Microsoft 365 password stops working when Microsoft turns off password authentication for SMTP AUTH (off by default from the end of December 2026).

Supported card issuers depend on the parsers in your OCR server (Huntington and U.S. Bank business cards today). BC sends every statement as **Credit Card Merchant**, and the server recognizes the issuer from the PDF, so adding a parser to the server needs no change in BC.

## Install

**From a release (no build tools needed)**
1. Download the `.app` file from the latest [release](../../releases).
2. In Business Central, open **Extension Management** → **Manage** → **Upload Extension** and select the file.
3. **Sandbox only:** in **Extension Management**, select the extension → **Configure** → turn on **Allow HttpClient Requests**, or BC can't reach the OCR server.
4. Assign the permission sets listed below to the people who use it.

**From source**
1. Clone this repo and open `CardStatementOCR-RequisitionApproval` in VS Code with the [AL Language extension](https://marketplace.visualstudio.com/items?itemName=ms-dynamics-smb.al).
2. Put your sandbox name and tenant ID in `.vscode/launch.json`, then run **AL: Download Symbols**.
3. Press **F5** to publish to your sandbox.

Always test in a sandbox before you install in production.

## Technical details

| | |
|---|---|
| Object ID range | 50100–50149 |
| Object prefix | `MID` |
| Dependencies | Base Application, System Application; OCR server |
| Permission set(s) | `MID OCR USER`, `MID CARD STMT`, `MID ENDPOINT SETUP` |
| Business Central | Online, version 25 or later |

## Need help with this app?

[Midstream Integrations](https://www.MidstreamIntegrations.com) installs, adapts and supports these extensions, and builds new ones for your process.
**[Book a 20-minute call](https://midstreamintegrations.com/book)** · intro@MidstreamIntegrations.com

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING](https://github.com/Midstream-Integrations/.github/blob/main/CONTRIBUTING.md).
Found a security problem? Please follow the [security policy](https://github.com/Midstream-Integrations/.github/blob/main/SECURITY.md) instead of opening a public issue.

## License

[MIT](LICENSE) © Midstream Integrations
