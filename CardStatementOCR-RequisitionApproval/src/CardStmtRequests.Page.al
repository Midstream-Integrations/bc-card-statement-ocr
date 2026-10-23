page 50113 "MID Card Stmt Requests"
{
    PageType = List;
    Caption = 'Card Statement Requests';
    SourceTable = "MID Card Stmt Request";
    SourceTableView = sorting("Entry No.") order(descending);
    ApplicationArea = All;
    UsageCategory = History;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Invoice No."; Rec."Invoice No.") { ToolTip = 'Purchase invoice the statement was sent from.'; }
                field(Merchant; Rec.Merchant) { ToolTip = 'Card issuer.'; }
                field(Cardholder; Rec.Cardholder) { ToolTip = 'Cardholder whose transactions were sent.'; }
                field("Card Last 4"; Rec."Card Last 4") { ToolTip = 'Last 4 digits of the card.'; }
                field("Manager Email"; Rec."Manager Email") { ToolTip = 'Who received the portal link.'; }
                field(Status; Rec.Status) { ToolTip = 'Sent, or Submitted once the lines were added to the invoice.'; }
                field("Sent At"; Rec."Sent At") { ToolTip = 'When the link was emailed.'; }
                field("Sent By"; Rec."Sent By") { ToolTip = 'BC user who sent it.'; }
                field("Submitted At"; Rec."Submitted At") { ToolTip = 'When the manager submitted.'; }
                field("Submitted By"; Rec."Submitted By") { ToolTip = 'Microsoft 365 account that submitted.'; }
                field("Portal URL"; Rec."Portal URL") { ToolTip = 'The link that was emailed.'; }
            }
        }
    }
}
