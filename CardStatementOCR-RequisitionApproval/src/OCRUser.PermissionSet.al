// One set for everyone who uses Card Statement OCR and Send for Requisition Approval.
// Endpoint API Setup is deliberately NOT included: the actions read the hosts through the
// "MID Card Stmt Mgt" codeunit, which carries its own read permission. Admins who maintain
// the setup page keep using "MID ENDPOINT SETUP".
permissionset 50111 "MID OCR USER"
{
    Assignable = true;
    Caption = 'OCR User (Card Statement OCR + Requisition Approval)';

    IncludedPermissionSets =
        "MID INV PROCESSING",      // D365 BASIC + D365 READ, Purchase Header/Line - the approval fields on the invoice
        "MID CARD STMT",        // card statement tables, Requisition Managers lookup, the codeunit
        "Email - Edit";         // Card Statement OCR sends the manager's email from BC

    Permissions =
        tabledata "Document Attachment" = RIMD,   // Send for Requisition Approval: vendor invoice + blank form, removed again if the send fails
        tabledata "MID Requisition Manager" = R,      // manager / 2nd approver lookups
        tabledata User = R,                       // the sender's email, CC'd on the approval emails
        tabledata "Report Selections" = R;       // finds the Requisition Form report
}
