enum 50110 "MID Card Merchant"
{
    Extensible = true;
    Caption = 'Card Statement Merchant';

    // The server id for each value lives in Codeunit "MID Card Stmt Mgt".MerchantId().
    // Auto lets the OCR server recognize the issuer from the PDF, so new issuers on the server need
    // no change here. Add a value only to force a specific parser.
    value(0; Auto) { Caption = 'Credit Card Merchant'; }
}
