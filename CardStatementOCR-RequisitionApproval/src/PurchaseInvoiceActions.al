pageextension 50104 "MID Purchase Invoice Ext" extends "Purchase Invoice"
{
    layout
    {
        addlast(General)
        {
            field("Mgr. Requisition Approval"; Rec.MgrRequisitionApproval)
            {
                ApplicationArea = All;
                ToolTip = 'Indicates the status of the manager requisition approval.';
            }
            field(HigherRequisitionApproval; Rec.HigherRequisitionApproval)
            {
                ApplicationArea = All;
                ToolTip = 'Indicates the status of the 2nd manager requisition approval.';
            }
        }
    }
    actions
    {
        addlast(Processing)
        {
            action("SendAsPdf")
            {
                ApplicationArea = All;
                Caption = 'Attach As PDF';
                Image = SendTo;

                trigger OnAction()

                begin
                    AttachAsPDFSilent();
                    Commit;
                    RenameReqForm();
                end;
            }
            group(MIDSendToOCR)
            {
                Caption = 'Send to OCR';
                Image = SendTo;
                ToolTip = 'Send a card statement to OCR.';

                // ---- Card statement OCR (receipts portal) ----
                action(MIDSendCardStatement)
                {
                    ApplicationArea = All;
                    Caption = 'Card Statement OCR';
                    Image = Import;
                    ToolTip = 'Upload a card statement, pick the cardholder, and email the requisition manager a link to attach receipts and G/L coding. Their submission becomes lines on this invoice.';

                    trigger OnAction()
                    var
                        CardStmtMgt: Codeunit "MID Card Stmt Mgt";
                    begin
                        CurrPage.SaveRecord();
                        CardStmtMgt.SendStatementForReceipts(Rec);
                        CurrPage.Update(false);
                    end;
                }
            }

            // ---- Requisition Approval ----
            action("Send for Requisition Approval")
            {
                ApplicationArea = All;
                Caption = 'Send for Requisition Approval';
                Image = SendTo;

                // Flow: pick manager -> optional 2nd approver -> upload the vendor invoice -> save + send.
                // Nothing is written until every prompt is answered. The OCR server (OCR Host + API key on
                // Endpoint API Setup) emails the manager the portal link; if that fails, the uploaded
                // invoice, the blank Requisition Form and the header changes are undone.
                trigger OnAction()
                var
                    Attachment: Record "Document Attachment";
                    RequisitionManager: Record "MID Requisition Manager";
                    RequisitionManagerEmail: Text;
                    RequisitionManagerName: Text;
                    Proceed: Boolean;
                    InvoiceNo: Code[20];
                    UserRec: Record User;
                    CurrentUserEmail: Text[100];

                    SecondaryApprovalNeeded: Boolean;
                    SecondRequisitionManager: Record "MID Requisition Manager";
                    SecondRequisitionManagerEmail: Text;
                    SecondRequisitionManagerName: Text;

                    CardStmtMgt: Codeunit "MID Card Stmt Mgt";

                    InvoiceBlob: Codeunit "Temp Blob";
                    InStr: InStream;
                    UploadFileName: Text;
                    Snapshot: Record "Purchase Header";
                    LastAttachmentId: Integer;
                    FailureReason: Text;

                begin
                    CurrPage.SaveRecord();    // keep the user's own edits on the page
                    COMMIT;

                    // === 1. Requisition Manager ===
                    Proceed := Dialog.Confirm('Ready to select the Requisition Manager in the next window?', false, 'Proceed', 'Cancel');
                    if not Proceed then
                        exit;

                    if PAGE.RunModal(PAGE::"MID Requisition Managers", RequisitionManager) <> ACTION::LookupOK then begin
                        Message('No Requisition Manager selected.');
                        exit;
                    end;
                    RequisitionManagerEmail := RequisitionManager."Email";
                    RequisitionManagerName := RequisitionManager."Name";
                    if RequisitionManagerEmail = '' then
                        Error('Requisition Manager %1 has no email address. Add it on the Requisition Managers page.', RequisitionManagerName);

                    // === 2. optional 2nd approver ===
                    SecondRequisitionManagerName := 'N/A';
                    SecondaryApprovalNeeded :=
                    Dialog.Confirm('Does this requisition require a secondary approval?', false, 'Yes', 'No');

                    if SecondaryApprovalNeeded then begin
                        if PAGE.RunModal(PAGE::"MID Requisition Managers", SecondRequisitionManager) = ACTION::LookupOK then begin
                            if SecondRequisitionManager."Email" = '' then
                                Error('Requisition Manager %1 has no email address. Add it on the Requisition Managers page.', SecondRequisitionManager."Name");
                            SecondRequisitionManagerEmail := SecondRequisitionManager."Email";
                            SecondRequisitionManagerName := SecondRequisitionManager."Name";
                        end else begin
                            Message('No secondary Requisition Manager selected. Secondary approval will be skipped.');
                            SecondaryApprovalNeeded := false;
                        end;
                    end;

                    // === 3. vendor invoice (held in memory until the send) ===
                    Proceed := Dialog.Confirm('Ready to select the vendor invoice to attach in the next window?', false, 'Proceed', 'Cancel');
                    if not Proceed then
                        exit;

                    if not UploadIntoStream('Select the vendor invoice', '', 'PDF files (*.pdf)|*.pdf', UploadFileName, InStr) then begin
                        Message('No attachment selected.');
                        exit;
                    end;
                    KeepUpload(InStr, InvoiceBlob);

                    // === 4. save everything in one transaction ===
                    Snapshot.Get(Rec."Document Type", Rec."No.");   // header values to put back if the send fails
                    LastAttachmentId := LastAttachmentIdOnInvoice();  // anything above this id was added by this run

                    UserRec.Get(UserSecurityId());
                    CurrentUserEmail := UserRec."Authentication Email";

                    Rec.Get(Rec."Document Type", Rec."No.");
                    Rec."RequisitionCreatorEmail" := CurrentUserEmail;
                    Rec."RequisitionCreatorName" := UserRec."Full Name";
                    Clear(Rec.HigherRequisitionEmail);
                    Clear(Rec.HigherRequisitionName);
                    Rec.Validate(HigherRequisitionEmail);
                    Rec.Validate(HigherRequisitionName);
                    if SecondaryApprovalNeeded then begin
                        Rec.Validate(HigherRequisitionApproval, Rec.HigherRequisitionApproval::"APPROVAL NOT SENT");
                        Rec.Validate(HigherRequisitionEmail, SecondRequisitionManagerEmail);
                        Rec.Validate(HigherRequisitionName, SecondRequisitionManagerName);
                    end else
                        Rec.Validate(HigherRequisitionApproval, Rec.HigherRequisitionApproval::"APPROVAL NOT NEEDED");
                    Rec.Modify(true);

                    SaveUploadedInvoice(InvoiceBlob, UploadFileName, LastAttachmentId, Attachment);
                    AttachAsPDFSilent();
                    RenameReqForm();

                    COMMIT;   // the OCR server reads the attachment from BC, so it must be saved before the call

                    InvoiceNo := Rec."No.";

                    // === 5. send - the OCR server emails the manager the portal link; on any failure undo step 4 ===
                    FailureReason := CardStmtMgt.SendRequisitionApproval(Rec, Attachment.SystemId, Attachment."File Name",
                        RequisitionManagerEmail, RequisitionManagerName, CurrentUserEmail);

                    if FailureReason <> '' then begin
                        UndoRequisitionSend(Snapshot, LastAttachmentId);
                        Error('Failed to send Approval request. Nothing was saved - the attachment and Requisition Form were removed. Please try again.\\%1', FailureReason);
                    end;

                    Rec.Get(Rec."Document Type", Rec."No.");
                    Rec."MgrRequisitionApproval" := Rec."MgrRequisitionApproval"::"APPROVAL SENT";
                    Rec.Modify(true);

                    Message(
                        'This has been sent to the Requisition Manager:\' +
                        'Invoice No. - %1\' +
                        'Manager Name. - %2\' +
                        'Attachment Name - %3\' +
                        '2nd Manager Name - %4',
                        InvoiceNo, RequisitionManagerName, Attachment."File Name", SecondRequisitionManagerName);

                    CurrPage.Update(false);
                end;
            }
        }
    }

    local procedure KeepUpload(var InStr: InStream; var InvoiceBlob: Codeunit "Temp Blob")
    var
        OutStr: OutStream;
    begin
        // the upload stream can only be read once - keep a copy until it's saved
        InvoiceBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, InStr);
    end;

    local procedure LastAttachmentIdOnInvoice() LastId: Integer
    var
        DocAtt: Record "Document Attachment";
    begin
        DocAtt.SetRange("Table ID", DATABASE::"Purchase Header");
        DocAtt.SetRange("No.", Rec."No.");
        if DocAtt.FindSet() then
            repeat
                if DocAtt.ID > LastId then
                    LastId := DocAtt.ID;
            until DocAtt.Next() = 0;
    end;

    local procedure SaveUploadedInvoice(var InvoiceBlob: Codeunit "Temp Blob"; FileName: Text; LastAttachmentId: Integer; var DocAtt: Record "Document Attachment")
    var
        RecRef: RecordRef;
        InStr: InStream;
    begin
        InvoiceBlob.CreateInStream(InStr);
        RecRef.GetTable(Rec);
        DocAtt.SaveAttachmentFromStream(InStr, RecRef, FileName);

        // read it back so SystemId and File Name are exactly what was stored
        DocAtt.Reset();
        DocAtt.SetRange("Table ID", DATABASE::"Purchase Header");
        DocAtt.SetRange("No.", Rec."No.");
        DocAtt.SetFilter(ID, '>%1', LastAttachmentId);
        if not DocAtt.FindFirst() then
            Error('The vendor invoice could not be attached to invoice %1.', Rec."No.");
    end;

    // Removes everything this run added (uploaded invoice + blank Requisition Form) and puts the
    // header fields back. Commits so the clean-up survives the Error that follows it.
    local procedure UndoRequisitionSend(Snapshot: Record "Purchase Header"; LastAttachmentId: Integer)
    var
        DocAtt: Record "Document Attachment";
    begin
        DocAtt.SetRange("Table ID", DATABASE::"Purchase Header");
        DocAtt.SetRange("No.", Snapshot."No.");
        DocAtt.SetFilter(ID, '>%1', LastAttachmentId);
        DocAtt.DeleteAll(true);

        Rec.Get(Snapshot."Document Type", Snapshot."No.");
        Rec.HigherRequisitionApproval := Snapshot.HigherRequisitionApproval;
        Rec.HigherRequisitionEmail := Snapshot.HigherRequisitionEmail;
        Rec.HigherRequisitionName := Snapshot.HigherRequisitionName;
        Rec.RequisitionCreatorEmail := Snapshot.RequisitionCreatorEmail;
        Rec.RequisitionCreatorName := Snapshot.RequisitionCreatorName;
        Rec.Modify(true);
        COMMIT;
    end;

    procedure AttachAsPDFSilent()
    var
        ReportSelections: Record "Report Selections";
        Usage: Enum "Report Selection Usage";
        PurchHeader: Record "Purchase Header";
    begin
        // Lock to the current document explicitly
        PurchHeader.Get(Rec."Document Type", Rec."No.");
        PurchHeader.SetRecFilter(); // belt-and-suspenders to pass an exact filter to the report

        // Use the Purchase Invoice usage (NOT Requisition)
        ReportSelections.SaveAsDocumentAttachment(
            Usage::Requisition.AsInteger(), // <-- important change
            PurchHeader,
            PurchHeader."No.",
            PurchHeader."Pay-to Vendor No.",
            false);
    end;


    procedure RenameReqForm()
    var
        DocAtt: Record "Document Attachment";
        CardStmtMgt: Codeunit "MID Card Stmt Mgt";
        newName: Text[250];
    begin
        // Target file name: RequisitionForm-[invoice no]
        newName := StrSubstNo('RequisitionForm-%1', Rec."No.");

        DocAtt.Reset();
        DocAtt.SetRange("Table ID", DATABASE::"Purchase Header");
        DocAtt.SetRange("No.", Rec."No.");

        // only the form the requisition report just saved (its default name contains the report id)
        DocAtt.SetFilter("File Name", CardStmtMgt.RequisitionFormFileFilter());

        if DocAtt.FindSet(false) then
            repeat
                if DocAtt."File Name" <> newName then begin
                    DocAtt.Validate("File Name", newName);
                    DocAtt.Modify(true);
                end;
            until DocAtt.Next() = 0
        else
            Error('No matching attachment found for invoice %1.', Rec."No.");
    end;

    procedure UrlEncode(Value: Text): Text
    begin
        Value := Value.Replace('#', '%23');
        exit(Value);
    end;
}

tableextension 50100 "MID Purchase Header Ext" extends "Purchase Header"
{
    fields
    {
        field(50100; "MgrRequisitionApproval"; Option)
        {
            Caption = 'Mgr. Requisition Approval';
            OptionMembers = "","APPROVAL NOT SENT","APPROVAL SENT","APPROVED";
            OptionCaption = ',Not Sent,Sent,Approved';
            DataClassification = CustomerContent;
            InitValue = 1; // Not Sent
        }
        field(50101; "HigherRequisitionApproval"; Option)
        {
            Caption = '2nd Requisition Approval';
            OptionMembers = "","APPROVAL NOT NEEDED","APPROVAL NOT SENT","APPROVAL SENT","APPROVED";
            OptionCaption = ',Not Needed,Not Sent,Sent,Approved';
            DataClassification = CustomerContent;
            InitValue = 1; // Not Needed
        }
        field(50102; "HigherRequisitionEmail"; Text[100])
        {
            Caption = '2nd Requisition Approval Email';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(50103; "HigherRequisitionName"; Text[100])
        {
            Caption = '2nd Requisition Approval Name';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(50104; "RequisitionCreatorEmail"; Text[100])
        {
            Caption = 'Email of Requisition Creator';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(50105; "RequisitionCreatorName"; Text[100])
        {
            Caption = 'Name of Requisition Creator';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}

pageextension 50105 "MID Purchase Invoices Ext" extends "Purchase Invoices"
{
    layout
    {
        addlast(Control1)
        {
            field("Mgr. Requisition Approval"; Rec."MgrRequisitionApproval")
            {
                ApplicationArea = All;
                ToolTip = 'Indicates the status of the manager requisition approval.';
            }
            field(HigherRequisitionApproval; Rec.HigherRequisitionApproval)
            {
                ApplicationArea = All;
                ToolTip = 'Indicates the status of the 2nd manager requisition approval.';
            }
        }
    }
}