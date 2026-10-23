// Called by the OCR server (service-to-service, Entra app) when a manager hits Submit:
//   POST .../api/midstream/cardStatement/v1.0/companies({id})/cardStatementBatches
//   POST .../cardStatementLines   (one per transaction, receipt as base64)
//   POST .../cardStatementBatches({id})/Microsoft.NAV.process   -> creates the invoice lines in ONE transaction
page 50110 "MID Card Stmt Batch API"
{
    PageType = API;
    APIPublisher = 'midstream';
    APIGroup = 'cardStatement';
    APIVersion = 'v1.0';
    EntityName = 'cardStatementBatch';
    EntitySetName = 'cardStatementBatches';
    SourceTable = "MID Card Stmt Batch";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    DeleteAllowed = false;
    ModifyAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { Editable = false; }
                field(invoiceId; Rec."Invoice Id") { }
                field(assignmentToken; Rec."Assignment Token") { }
                field(submittedBy; Rec."Submitted By") { }
                field(cardholder; Rec.Cardholder) { }
                field(submittedAt; Rec."Submitted At") { }
                field(status; Rec.Status) { Editable = false; }
                field(linesCreated; Rec."Lines Created") { Editable = false; }
            }
        }
    }

    [ServiceEnabled]
    procedure Process(var ActionContext: WebServiceActionContext)
    var
        CardStmtMgt: Codeunit "MID Card Stmt Mgt";
    begin
        CardStmtMgt.ProcessBatch(Rec);
        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"MID Card Stmt Batch API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;
}

page 50111 "MID Card Stmt Line API"
{
    PageType = API;
    APIPublisher = 'midstream';
    APIGroup = 'cardStatement';
    APIVersion = 'v1.0';
    EntityName = 'cardStatementLine';
    EntitySetName = 'cardStatementLines';
    SourceTable = "MID Card Stmt Line";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    DeleteAllowed = false;
    ModifyAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { Editable = false; }
                field(batchId; Rec."Batch Id") { }
                field(lineNo; Rec."Line No.") { }
                field(transactionDate; Rec."Transaction Date") { }
                field(description; Rec.Description) { }
                field(reference; Rec.Reference) { }
                field(amount; Rec.Amount) { }
                field(glAccountNo; Rec."G/L Account No.") { }
                field(dimension1Code; Rec."Dimension 1 Code") { }
                field(dimension2Code; Rec."Dimension 2 Code") { }
                field(receiptFileName; Rec."Receipt File Name") { }
                field(receiptBase64; ReceiptBase64) { }
                field(receiptCheck; Rec."Receipt Check") { }
                field(receiptNote; Rec."Receipt Note") { }
            }
        }
    }

    var
        ReceiptBase64: Text;
        UnknownBatchErr: Label 'Card statement batch %1 does not exist.', Comment = '%1 = batch id';
        BatchClosedErr: Label 'Card statement batch %1 has already been processed.', Comment = '%1 = batch id';

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        Batch: Record "MID Card Stmt Batch";
        Base64Convert: Codeunit "Base64 Convert";
        OutStr: OutStream;
    begin
        if not Batch.GetBySystemId(Rec."Batch Id") then
            Error(UnknownBatchErr, Rec."Batch Id");
        if Batch.Status <> Batch.Status::Pending then
            Error(BatchClosedErr, Rec."Batch Id");
        if ReceiptBase64 <> '' then begin
            Rec.Receipt.CreateOutStream(OutStr);
            Base64Convert.FromBase64(ReceiptBase64, OutStr);
        end;
        exit(true);
    end;
}
