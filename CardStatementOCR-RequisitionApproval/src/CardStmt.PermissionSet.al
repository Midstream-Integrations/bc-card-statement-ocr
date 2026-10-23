permissionset 50110 "MID CARD STMT"
{
    Assignable = true;
    Caption = 'Card Statement OCR';

    Permissions =
        tabledata "MID Card Stmt Request" = RIMD,
        tabledata "MID Card Stmt Batch" = RIMD,
        tabledata "MID Card Stmt Line" = RIMD,
        tabledata "MID Requisition Manager" = R,     // manager lookup in the OCR dialog (read-only)
        table "MID Card Stmt Request" = X,
        table "MID Card Stmt Batch" = X,
        table "MID Card Stmt Line" = X,
        page "MID Card Stmt Batch API" = X,
        page "MID Card Stmt Line API" = X,
        page "MID Card Stmt Requests" = X,
        codeunit "MID Card Stmt Mgt" = X,
        report "MID Requisition Form" = X;       // the blank form attached to the invoice
}
