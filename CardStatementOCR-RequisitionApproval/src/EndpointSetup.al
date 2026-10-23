table 50103 "MID Endpoint API"
{
    Caption = 'Endpoint API';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
        }
        field(3; "OCR Host"; Text[100])
        {
            Caption = 'OCR Host';
            DataClassification = CustomerContent;
        }
        field(4; "Requisition Form Report ID"; Integer)
        {
            Caption = 'Requisition Form Report ID';
            DataClassification = CustomerContent;
            TableRelation = AllObjWithCaption."Object ID" where("Object Type" = const(Report));

            trigger OnValidate()
            var
                CardStmtMgt: Codeunit "MID Card Stmt Mgt";
            begin
                // the form is printed through Report Selections (usage "Requisition") so it can be swapped without code
                CardStmtMgt.SetRequisitionFormReport("Requisition Form Report ID");
            end;
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }
}
page 50103 "MID Endpoint API Setup"
{
    Caption = 'Endpoint API Setup';
    PageType = Card;
    SourceTable = "MID Endpoint API";
    ApplicationArea = All;
    UsageCategory = Administration;

    // Make sure the page is editable
    Editable = true;
    InsertAllowed = true;
    ModifyAllowed = true;
    DeleteAllowed = false;

    layout
    {
        area(content)
        {
            group(OCR)
            {
                Caption = 'OCR server (Card Statement OCR and Requisition Approval)';
                field(OCRHost; Rec."OCR Host")
                {
                    ApplicationArea = All;
                    Caption = 'OCR Host';
                    ToolTip = 'Hostname of the OCR server (e.g., ocr.example.com). https:// is added automatically.';
                }
                field(OCRApiKey; ApiKeyInput)
                {
                    ApplicationArea = All;
                    Caption = 'OCR API Key';
                    ExtendedDatatype = Masked;
                    ToolTip = 'Shared key sent as X-API-Key to the OCR server (OCR_API_KEY). Stored in isolated storage, not in this table. Leave blank to keep the current key.';
                    trigger OnValidate()
                    var
                        CardStmtMgt: Codeunit "MID Card Stmt Mgt";
                    begin
                        if ApiKeyInput = '' then
                            exit;
                        CardStmtMgt.SetApiKey(ApiKeyInput);
                        ApiKeyInput := '';
                        ApiKeyIsSet := true;
                    end;
                }
                field(OCRApiKeySet; ApiKeyIsSet)
                {
                    ApplicationArea = All;
                    Caption = 'OCR API Key Set';
                    Editable = false;
                    ToolTip = 'Whether an OCR API key has been stored.';
                }
            }
            group(Requisition)
            {
                Caption = 'Requisition Form';
                field(RequisitionFormReportID; Rec."Requisition Form Report ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'The report that prints your blank requisition form. It is attached to the invoice when approval is requested and stamped with cost, G/L account and approver when the manager submits.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(TestOCRConnection)
            {
                ApplicationArea = All;
                Caption = 'Test OCR Connection';
                Image = TestFile;
                ToolTip = 'Calls the OCR server with the stored host and key and lists the statement types it can read.';
                trigger OnAction()
                var
                    CardStmtMgt: Codeunit "MID Card Stmt Mgt";
                begin
                    CardStmtMgt.TestConnection();
                end;
            }
        }
        area(Promoted)
        {
            actionref(TestOCRConnection_Promoted; TestOCRConnection) { }
        }
    }

    var
        ApiKeyInput: Text;
        ApiKeyIsSet: Boolean;

    trigger OnOpenPage()
    var
        R: Record "MID Endpoint API";
        CardStmtMgt: Codeunit "MID Card Stmt Mgt";
    begin
        // Ensure the SETUP record exists…
        if not R.Get('SETUP') then begin
            R.Init();
            R."Primary Key" := 'SETUP';
            R.Insert(true);
        end;

        // …and make sure the page is actually looking at it
        Rec.Get('SETUP');
        ApiKeyIsSet := CardStmtMgt.HasApiKey();
    end;
}
