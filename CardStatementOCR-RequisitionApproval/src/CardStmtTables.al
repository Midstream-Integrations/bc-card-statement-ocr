table 50110 "MID Card Stmt Request"
{
    Caption = 'Card Statement Request';
    DataClassification = CustomerContent;
    LookupPageId = "MID Card Stmt Requests";
    DrillDownPageId = "MID Card Stmt Requests";

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Entry No.'; AutoIncrement = true; }
        field(2; "Invoice Id"; Guid) { Caption = 'Invoice Id'; }
        field(3; "Invoice No."; Code[20]) { Caption = 'Invoice No.'; }
        field(4; Merchant; Enum "MID Card Merchant") { Caption = 'Merchant'; }
        field(5; "Statement Id"; Text[50]) { Caption = 'Statement Id'; }
        field(6; Cardholder; Text[100]) { Caption = 'Cardholder'; }
        field(7; "Card Last 4"; Code[4]) { Caption = 'Card Last 4'; }
        field(8; "Manager Email"; Text[250]) { Caption = 'Manager Email'; DataClassification = EndUserIdentifiableInformation; }
        field(9; "Portal URL"; Text[250]) { Caption = 'Portal URL'; ExtendedDatatype = URL; }
        field(10; Token; Text[64]) { Caption = 'Token'; }
        field(11; Status; Option) { Caption = 'Status'; OptionMembers = Sent,Submitted; OptionCaption = 'Sent,Submitted'; }
        field(12; "Sent At"; DateTime) { Caption = 'Sent At'; }
        field(13; "Sent By"; Code[50]) { Caption = 'Sent By'; DataClassification = EndUserIdentifiableInformation; }
        field(14; "Submitted At"; DateTime) { Caption = 'Submitted At'; }
        field(15; "Submitted By"; Text[250]) { Caption = 'Submitted By'; DataClassification = EndUserIdentifiableInformation; }
    }
    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Invoice; "Invoice Id") { }
        key(Token; Token) { }
    }
}

table 50111 "MID Card Stmt Batch"
{
    Caption = 'Card Statement Batch';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Entry No.'; AutoIncrement = true; }
        field(2; "Invoice Id"; Guid) { Caption = 'Invoice Id'; }
        field(3; "Assignment Token"; Text[64]) { Caption = 'Assignment Token'; }
        field(4; "Submitted By"; Text[250]) { Caption = 'Submitted By'; DataClassification = EndUserIdentifiableInformation; }
        field(5; Cardholder; Text[100]) { Caption = 'Cardholder'; }
        field(6; Status; Option) { Caption = 'Status'; OptionMembers = Pending,Processed; OptionCaption = 'Pending,Processed'; }
        field(7; "Processed At"; DateTime) { Caption = 'Processed At'; }
        field(8; "Lines Created"; Integer) { Caption = 'Lines Created'; }
        field(9; "Submitted At"; DateTime) { Caption = 'Submitted At'; }      // when the manager pressed Submit (UTC, sent by the OCR server)
    }
    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Token; "Assignment Token", Status) { }
    }
}

table 50112 "MID Card Stmt Line"
{
    Caption = 'Card Statement Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer) { Caption = 'Entry No.'; AutoIncrement = true; }
        field(2; "Batch Id"; Guid) { Caption = 'Batch Id'; }                 // SystemId of MID Card Stmt Batch
        field(3; "Line No."; Integer) { Caption = 'Line No.'; }
        field(4; "Transaction Date"; Date) { Caption = 'Transaction Date'; }
        field(5; Description; Text[100]) { Caption = 'Description'; }
        field(6; Reference; Text[35]) { Caption = 'Reference'; }
        field(7; Amount; Decimal) { Caption = 'Amount'; AutoFormatType = 1; }   // purchases +, credits -
        field(8; "G/L Account No."; Code[20]) { Caption = 'G/L Account No.'; }
        field(9; "Dimension 1 Code"; Code[20]) { Caption = 'Shortcut Dimension 1 Code'; }
        field(10; "Dimension 2 Code"; Code[20]) { Caption = 'Shortcut Dimension 2 Code'; }
        field(11; "Receipt File Name"; Text[250]) { Caption = 'Receipt File Name'; }
        field(12; Receipt; Blob) { Caption = 'Receipt'; }
        field(13; "Receipt Check"; Text[30]) { Caption = 'Receipt Check'; }      // match | found | mismatch | unreadable
        field(14; "Receipt Note"; Text[250]) { Caption = 'Receipt Note'; }
        field(15; "Purchase Line No."; Integer) { Caption = 'Purchase Line No.'; }
    }
    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Batch; "Batch Id", "Line No.") { }
    }
}
