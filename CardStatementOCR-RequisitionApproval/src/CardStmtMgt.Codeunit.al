codeunit 50110 "MID Card Stmt Mgt"
{
    // "MID Endpoint API" = r: actions read the hosts through this codeunit, so users don't need access to Endpoint API Setup
    Permissions = tabledata "Purchase Line" = rim, tabledata "Purch. Comment Line" = rim, tabledata "Document Attachment" = rim,
        tabledata "MID Endpoint API" = r, tabledata "Report Selections" = rimd;

    var
        ApiKeyStorageTok: Label 'MID_OCR_APIKEY', Locked = true;
        NoSetupErr: Label 'The OCR Host is not set up. Ask IT to fill it in on the Endpoint API Setup page.';
        NoApiKeyErr: Label 'The OCR API key has not been set. Enter it on the Endpoint API Setup page.';
        CannotReachErr: Label 'Could not reach the OCR server at %1. Check the OCR Host on Endpoint API Setup and that the server is running.\\Details: %2', Comment = '%1 = URL, %2 = platform error';
        ApiErr: Label 'The OCR server returned an error (%1):\%2', Comment = '%1 = HTTP status, %2 = message';
        SelectPdfTxt: Label 'Select the card statement PDF';
        NoCardholdersErr: Label 'The statement was read, but no cardholder on it has transactions.';
        PickCardholderTxt: Label 'Statement closing %1 - which cardholder is this invoice for?', Comment = '%1 = closing date';
        NoManagerErr: Label 'Requisition Manager %1 has no email address. Add it on the Requisition Managers page.', Comment = '%1 = manager name';
        SelectMerchantTxt: Label 'Select the card merchant';
        EmailFailedErr: Label 'The portal link was created but the email could not be sent:\%1\\Link: %2', Comment = '%1 = error, %2 = URL';
        SentMsg: Label 'Sent %1''s transactions to %2.\They''ll get an email with a link to upload receipts and G/L coding; the lines will appear on this invoice when they submit.\2nd Manager Name - %3', Comment = '%1 = cardholder, %2 = email, %3 = 2nd approver or N/A';
        SubjectTxt: Label 'Receipts needed: %1 card statement (closing %2)', Comment = '%1 = cardholder, %2 = date';
        EmailBodyTxt: Label '<p>Hi %1,</p><p>The card statement for <b>%2</b> (closing %3) is ready for receipts on purchase invoice <b>%4</b>.</p><p>For each transaction, upload the receipt and enter the G/L account%6, then press Submit.</p><p><a href="%5">Open the receipts portal</a></p><p>Sign in with your company Microsoft 365 account. If the link opens to a list, pick invoice %4.</p>', Comment = '%1 = manager, %2 = cardholder, %3 = closing date, %4 = invoice no., %5 = URL, %6 = optional dimension names';
        InvoiceNotFoundErr: Label 'The purchase invoice for this submission no longer exists.';
        AlreadySubmittedErr: Label 'These transactions were already added to purchase invoice %1.', Comment = '%1 = invoice no.';
        NoLinesErr: Label 'The submission contains no lines.';
        GLNotFoundTxt: Label 'G/L %1 not found - left blank. Charge %2: re-enter the cost after choosing the account.', Comment = '%1 = account, %2 = amount';
        DimNotFoundTxt: Label '%1 %2 not found - left blank.', Comment = '%1 = dimension, %2 = value';
        ReqFormNameTxt: Label 'RequisitionForm-%1', Locked = true, Comment = '%1 = invoice no. (same name Send for Requisition Approval uses)';
        ReqFormMissingTxt: Label 'Requisition form not found on the invoice - it was not signed.';
        ReqFormSignFailedTxt: Label 'Requisition form could not be signed: %1', Comment = '%1 = error';
        MultipleGLTxt: Label 'MULTIPLE', Locked = true;
        ConnectionOkMsg: Label 'Connected. The OCR server can read: %1', Comment = '%1 = merchant list';
        NoReqFormReportErr: Label 'No Requisition Form report is set. Choose one on the Endpoint API Setup page.';
        ProcessingStmtTxt: Label 'Processing the statement - this will take several seconds.\\Please do not close this window until it finishes.';

    // ================================================================ start: Purchase Invoice action
    procedure SendStatementForReceipts(var PurchHeader: Record "Purchase Header")
    var
        Request: Record "MID Card Stmt Request";
        RequisitionManager: Record "MID Requisition Manager";
        Merchant: Enum "MID Card Merchant";
        StmtJson, Holder, AsgJson : JsonObject;
        Holders: JsonArray;
        Tok: JsonToken;
        StmtBlob: Codeunit "Temp Blob";
        InStr: InStream;
        FileName, ManagerEmail, ManagerName, Options, Url, CardholderName, ClosingDate : Text;
        SecondEmail, SecondName : Text;
        i, Choice : Integer;
        SecondNeeded: Boolean;
        Window: Dialog;
    begin
        PurchHeader.TestField("Document Type", PurchHeader."Document Type"::Invoice);
        PurchHeader.TestField(Status, PurchHeader.Status::Open);

        // 1. merchant
        if not SelectMerchant(Merchant) then
            exit;

        // 2. requisition manager - same prompts as Send for Requisition Approval
        if not Dialog.Confirm('Ready to select the Requisition Manager in the next window?', false, 'Proceed', 'Cancel') then
            exit;
        if Page.RunModal(Page::"MID Requisition Managers", RequisitionManager) <> Action::LookupOK then begin
            Message('No Requisition Manager selected.');
            exit;
        end;
        ManagerEmail := RequisitionManager.Email;
        ManagerName := RequisitionManager.Name;
        if ManagerEmail = '' then
            Error(NoManagerErr, ManagerName);

        // 2b. optional 2nd approver - same prompt as Send for Requisition Approval
        SecondNeeded := SelectSecondApprover(SecondEmail, SecondName);

        // 3. statement PDF -> OCR server parses it and returns the cardholders on it
        if not Dialog.Confirm('Ready to select the card statement PDF in the next window?', false, 'Proceed', 'Cancel') then
            exit;
        if not UploadIntoStream(SelectPdfTxt, '', 'PDF files (*.pdf)|*.pdf', FileName, InStr) then
            exit;
        KeepStatement(InStr, StmtBlob);   // the stream is used up by the upload - keep a copy to attach
        StmtBlob.CreateInStream(InStr);
        Window.Open(ProcessingStmtTxt);   // parsing can take several seconds - tell the user not to close out
        StmtJson := PostStatement(MerchantId(Merchant), FileName, InStr);
        Window.Close();
        ClosingDate := GetText(StmtJson, 'closingDate');
        StmtJson.Get('cardholders', Tok);
        Holders := Tok.AsArray();
        if Holders.Count() = 0 then
            Error(NoCardholdersErr);

        // 4. pick the cardholder (labels come from the server already comma-free for StrMenu)
        for i := 0 to Holders.Count() - 1 do begin
            Holders.Get(i, Tok);
            if i > 0 then
                Options += ',';
            Options += GetText(Tok.AsObject(), 'label');
        end;
        Choice := StrMenu(Options, 0, StrSubstNo(PickCardholderTxt, ClosingDate));
        if Choice = 0 then
            exit;
        Holders.Get(Choice - 1, Tok);
        Holder := Tok.AsObject();
        CardholderName := GetText(Holder, 'name');

        // 5. create the portal assignment and email the manager
        AsgJson := PostAssignment(GetText(StmtJson, 'statementId'), GetText(Holder, 'last4'), PurchHeader, ManagerEmail, ManagerName);
        Url := GetText(AsgJson, 'url');
        SendManagerEmail(PurchHeader, ManagerEmail, ManagerName, CardholderName, ClosingDate, Url);
        SetApprovers(PurchHeader, SecondNeeded, SecondEmail, SecondName);
        MarkApprovalSent(PurchHeader);

        Request.Init();
        Request."Invoice Id" := PurchHeader.SystemId;
        Request."Invoice No." := PurchHeader."No.";
        Request.Merchant := Merchant;
        Request."Statement Id" := CopyStr(GetText(StmtJson, 'statementId'), 1, MaxStrLen(Request."Statement Id"));
        Request.Cardholder := CopyStr(CardholderName, 1, MaxStrLen(Request.Cardholder));
        Request."Card Last 4" := CopyStr(GetText(Holder, 'last4'), 1, MaxStrLen(Request."Card Last 4"));
        Request."Manager Email" := CopyStr(ManagerEmail, 1, MaxStrLen(Request."Manager Email"));
        Request."Portal URL" := CopyStr(Url, 1, MaxStrLen(Request."Portal URL"));
        Request.Token := CopyStr(GetText(AsgJson, 'token'), 1, MaxStrLen(Request.Token));
        Request."Sent At" := CurrentDateTime();
        Request."Sent By" := CopyStr(UserId(), 1, MaxStrLen(Request."Sent By"));
        Request.Insert(true);
        Commit();   // email is out and the request is logged - keep that even if the form below fails

        AttachStatement(PurchHeader, StmtBlob, FileName);
        AttachRequisitionForm(PurchHeader);

        Message(SentMsg, CardholderName, ManagerEmail, SecondName);
    end;

    local procedure PostJson(PathAndQuery: Text; Body: JsonObject): JsonObject
    var
        Content: HttpContent;
        Headers: HttpHeaders;
        BodyText: Text;
    begin
        Body.WriteTo(BodyText);
        Content.WriteFrom(BodyText);
        Content.GetHeaders(Headers);
        if Headers.Contains('Content-Type') then
            Headers.Remove('Content-Type');
        Headers.Add('Content-Type', 'application/json');
        exit(CallApi('POST', PathAndQuery, Content, true));
    end;

    local procedure SelectMerchant(var Merchant: Enum "MID Card Merchant"): Boolean
    var
        Ordinals: List of [Integer];
        Options: Text;
        Choice, i : Integer;
    begin
        Ordinals := Enum::"MID Card Merchant".Ordinals();
        if Ordinals.Count() = 1 then begin   // nothing to choose
            Merchant := Enum::"MID Card Merchant".FromInteger(Ordinals.Get(1));
            exit(true);
        end;
        for i := 1 to Ordinals.Count() do begin
            if i > 1 then
                Options += ',';
            Options += Format(Enum::"MID Card Merchant".FromInteger(Ordinals.Get(i)));
        end;
        Choice := StrMenu(Options, 1, SelectMerchantTxt);
        if Choice = 0 then
            exit(false);
        Merchant := Enum::"MID Card Merchant".FromInteger(Ordinals.Get(Choice));
        exit(true);
    end;

    local procedure MerchantId(Merchant: Enum "MID Card Merchant"): Text
    begin
        // must match the ids in parsers.py MERCHANTS on the OCR server
        case Merchant of
            Merchant::Auto:
                exit('auto');
        end;
    end;

    local procedure SendManagerEmail(PurchHeader: Record "Purchase Header"; ManagerEmail: Text; ManagerName: Text; Cardholder: Text; ClosingDate: Text; Url: Text)
    var
        EmailMessage: Codeunit "Email Message";
        Email: Codeunit Email;
        Greeting: Text;
    begin
        Greeting := ManagerName;
        if Greeting = '' then
            Greeting := ManagerEmail;
        EmailMessage.Create(ManagerEmail, StrSubstNo(SubjectTxt, Cardholder, ClosingDate),
            StrSubstNo(EmailBodyTxt, Greeting, Cardholder, ClosingDate, PurchHeader."No.", Url, DimensionHint()), true);
        ClearLastError();
        if not TrySendEmail(Email, EmailMessage) then
            Error(EmailFailedErr, GetLastErrorText(), Url);
    end;

    // ' and the Department and Project codes' - built from the company's own shortcut dimensions
    local procedure DimensionHint() Hint: Text
    var
        GLSetup: Record "General Ledger Setup";
        Dim1, Dim2 : Text;
        TwoDimsTxt: Label ' and the %1 and %2 codes', Comment = '%1, %2 = dimension names';
        OneDimTxt: Label ' and the %1 code', Comment = '%1 = dimension name';
    begin
        if not GLSetup.Get() then
            exit('');
        Dim1 := DimensionName(GLSetup."Shortcut Dimension 1 Code");
        Dim2 := DimensionName(GLSetup."Shortcut Dimension 2 Code");
        if (Dim1 <> '') and (Dim2 <> '') then
            exit(StrSubstNo(TwoDimsTxt, Dim1, Dim2));
        if Dim1 <> '' then
            exit(StrSubstNo(OneDimTxt, Dim1));
        if Dim2 <> '' then
            exit(StrSubstNo(OneDimTxt, Dim2));
    end;

    local procedure DimensionName(DimCode: Code[20]): Text
    var
        Dimension: Record Dimension;
    begin
        if DimCode = '' then
            exit('');
        if Dimension.Get(DimCode) and (Dimension.Name <> '') then
            exit(Dimension.Name);
        exit(DimCode);
    end;

    // ================================================================ 2nd approver (mirrors Send for Requisition Approval)
    local procedure SelectSecondApprover(var SecondEmail: Text; var SecondName: Text): Boolean
    var
        SecondManager: Record "MID Requisition Manager";
    begin
        SecondEmail := '';
        SecondName := 'N/A';
        if not Dialog.Confirm('Does this requisition require a secondary approval?', false, 'Yes', 'No') then
            exit(false);
        if Page.RunModal(Page::"MID Requisition Managers", SecondManager) <> Action::LookupOK then begin
            Message('No secondary Requisition Manager selected. Secondary approval will be skipped.');
            exit(false);
        end;
        if SecondManager.Email = '' then
            Error(NoManagerErr, SecondManager.Name);
        SecondEmail := SecondManager.Email;
        SecondName := SecondManager.Name;
        exit(true);
    end;

    // Same header fields Send for Requisition Approval fills: creator, and the 2nd approver if one was picked.
    // Runs after the email is sent and before the Commit, so a failed send leaves the header untouched.
    local procedure SetApprovers(var PurchHeader: Record "Purchase Header"; SecondNeeded: Boolean; SecondEmail: Text; SecondName: Text)
    var
        UserRec: Record User;
    begin
        PurchHeader.Get(PurchHeader."Document Type", PurchHeader."No.");
        if UserRec.Get(UserSecurityId()) then begin
            PurchHeader.RequisitionCreatorEmail := CopyStr(UserRec."Authentication Email", 1, MaxStrLen(PurchHeader.RequisitionCreatorEmail));
            PurchHeader.RequisitionCreatorName := CopyStr(UserRec."Full Name", 1, MaxStrLen(PurchHeader.RequisitionCreatorName));
        end;
        Clear(PurchHeader.HigherRequisitionEmail);
        Clear(PurchHeader.HigherRequisitionName);
        PurchHeader.Validate(HigherRequisitionEmail);
        PurchHeader.Validate(HigherRequisitionName);
        if SecondNeeded then begin
            PurchHeader.Validate(HigherRequisitionApproval, PurchHeader.HigherRequisitionApproval::"APPROVAL NOT SENT");
            PurchHeader.Validate(HigherRequisitionEmail, CopyStr(SecondEmail, 1, MaxStrLen(PurchHeader.HigherRequisitionEmail)));
            PurchHeader.Validate(HigherRequisitionName, CopyStr(SecondName, 1, MaxStrLen(PurchHeader.HigherRequisitionName)));
        end else
            // re-sent without a 2nd approver: clear any status left from an earlier send, so the portal
            // stamps "Approved By:" and no 2nd-approval email goes out
            PurchHeader.Validate(HigherRequisitionApproval, PurchHeader.HigherRequisitionApproval::"APPROVAL NOT NEEDED");
        PurchHeader.Modify(true);
    end;

    // Same status the Send for Requisition Approval action sets after its request goes out.
    // Only reached once the email has actually been sent (SendManagerEmail errors out otherwise).
    local procedure MarkApprovalSent(var PurchHeader: Record "Purchase Header")
    begin
        PurchHeader.Get(PurchHeader."Document Type", PurchHeader."No.");
        PurchHeader.MgrRequisitionApproval := PurchHeader.MgrRequisitionApproval::"APPROVAL SENT";
        PurchHeader.Modify(true);
    end;

    [TryFunction]
    local procedure TrySendEmail(var Email: Codeunit Email; var EmailMessage: Codeunit "Email Message")
    begin
        // raises the real reason (no default account, connector error...) so it can be shown with the link
        if not Email.Send(EmailMessage, Enum::"Email Scenario"::Default) then
            Error(GetLastErrorText());
    end;

    // ================================================================ finish: called by the API when the manager submits
    procedure ProcessBatch(var Batch: Record "MID Card Stmt Batch")
    var
        PurchHeader: Record "Purchase Header";
        StmtLine: Record "MID Card Stmt Line";
        Previous: Record "MID Card Stmt Batch";
        CodingNotes, GLString, FormGL : Text;
        NextLineNo, Created : Integer;
        Total: Decimal;
    begin
        Batch.TestField(Status, Batch.Status::Pending);
        if not PurchHeader.GetBySystemId(Batch."Invoice Id") then
            Error(InvoiceNotFoundErr);
        PurchHeader.TestField("Document Type", PurchHeader."Document Type"::Invoice);
        PurchHeader.TestField(Status, PurchHeader.Status::Open);

        Previous.SetCurrentKey("Assignment Token", Status);
        Previous.SetRange("Assignment Token", Batch."Assignment Token");
        Previous.SetRange(Status, Previous.Status::Processed);
        if not Previous.IsEmpty() then
            Error(AlreadySubmittedErr, PurchHeader."No.");

        StmtLine.SetCurrentKey("Batch Id", "Line No.");
        StmtLine.SetRange("Batch Id", Batch.SystemId);
        if not StmtLine.FindSet(true) then
            Error(NoLinesErr);

        NextLineNo := GetNextLineNo(PurchHeader);
        repeat
            CodingNotes := CreatePurchLine(PurchHeader, StmtLine, NextLineNo);
            AttachReceipt(PurchHeader, StmtLine, NextLineNo);
            AddReceiptComment(PurchHeader, StmtLine, NextLineNo, CodingNotes);
            StmtLine."Purchase Line No." := NextLineNo;
            StmtLine.Modify();

            // requisition form: total of every transaction, and the G/L string if they all use the same one
            Total += StmtLine.Amount;
            GLString := GLStringOf(StmtLine);
            if GLString <> '' then
                if FormGL = '' then
                    FormGL := GLString
                else
                    if FormGL <> GLString then
                        FormGL := MultipleGLTxt;
            NextLineNo += 10000;
            Created += 1;
        until StmtLine.Next() = 0;

        Batch.Status := Batch.Status::Processed;
        Batch."Processed At" := CurrentDateTime();
        Batch."Lines Created" := Created;
        if Batch."Submitted At" = 0DT then
            Batch."Submitted At" := Batch."Processed At";   // OCR server didn't send it - use processing time
        Batch.Modify();
        MarkRequestSubmitted(Batch);

        // the manager has reviewed and coded every charge -> requisition is approved
        PurchHeader.Get(PurchHeader."Document Type", PurchHeader."No.");
        PurchHeader.MgrRequisitionApproval := PurchHeader.MgrRequisitionApproval::APPROVED;
        PurchHeader.Modify(true);


        SignRequisitionForm(PurchHeader, Batch, Total, FormGL);
    end;

    // ================================================================ statement PDF on the invoice
    local procedure KeepStatement(var InStr: InStream; var StmtBlob: Codeunit "Temp Blob")
    var
        OutStr: OutStream;
    begin
        StmtBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, InStr);
    end;

    local procedure AttachStatement(PurchHeader: Record "Purchase Header"; var StmtBlob: Codeunit "Temp Blob"; FileName: Text)
    var
        DocAttachment: Record "Document Attachment";
        RecRef: RecordRef;
        InStr: InStream;
    begin
        if not StmtBlob.HasValue() then
            exit;
        StmtBlob.CreateInStream(InStr);
        RecRef.GetTable(PurchHeader);
        DocAttachment.SaveAttachmentFromStream(InStr, RecRef, FileName);
    end;

    // ================================================================ requisition form
    // Send: attach the same Requisition Form PDF that Send for Requisition Approval attaches.
    local procedure AttachRequisitionForm(PurchHeader: Record "Purchase Header")
    var
        ReportSelections: Record "Report Selections";
        DocAtt: Record "Document Attachment";
    begin
        if FindRequisitionForm(PurchHeader, DocAtt) then
            exit;   // already on the invoice (re-send, or Requisition Approval made it)

        PurchHeader.SetRecFilter();
        ReportSelections.SaveAsDocumentAttachment(
            Enum::"Report Selection Usage"::Requisition.AsInteger(),
            PurchHeader,
            PurchHeader."No.",
            PurchHeader."Pay-to Vendor No.",
            false);

        DocAtt.Reset();
        DocAtt.SetRange("Table ID", Database::"Purchase Header");
        DocAtt.SetRange("No.", PurchHeader."No.");
        DocAtt.SetFilter("File Name", RequisitionFormFileFilter());   // default name the report saves with
        if DocAtt.FindLast() then begin
            DocAtt.Validate("File Name", StrSubstNo(ReqFormNameTxt, PurchHeader."No."));
            DocAtt.Modify(true);
        end;
    end;

    local procedure FindRequisitionForm(PurchHeader: Record "Purchase Header"; var DocAtt: Record "Document Attachment"): Boolean
    begin
        DocAtt.Reset();
        DocAtt.SetRange("Table ID", Database::"Purchase Header");
        DocAtt.SetRange("No.", PurchHeader."No.");
        DocAtt.SetRange("File Name", StrSubstNo(ReqFormNameTxt, PurchHeader."No."));
        exit(DocAtt.FindLast());
    end;

    // Submit: fill Cost, G/L Account and Approved By on that PDF (stamped by the OCR server).
    // Never fails the submission - problems become a comment on the invoice instead.
    local procedure SignRequisitionForm(PurchHeader: Record "Purchase Header"; Batch: Record "MID Card Stmt Batch"; Total: Decimal; FormGL: Text)
    var
        DocAtt: Record "Document Attachment";
        TempBlob: Codeunit "Temp Blob";
        Base64Convert: Codeunit "Base64 Convert";
        Body: JsonObject;
        Stamped: Text;
        OutStr: OutStream;
        InStr: InStream;
    begin
        if not FindRequisitionForm(PurchHeader, DocAtt) then begin
            AddHeaderComment(PurchHeader, ReqFormMissingTxt);
            exit;
        end;

        TempBlob.CreateOutStream(OutStr);
        DocAtt."Document Reference ID".ExportStream(OutStr);
        TempBlob.CreateInStream(InStr);

        Body.Add('pdfBase64', Base64Convert.ToBase64(InStr));
        Body.Add('cost', Total);
        Body.Add('glAccount', FormGL);
        Body.Add('signedBy', Batch."Submitted By");
        Body.Add('signedAt', Format(Batch."Submitted At", 0, 9));   // ISO 8601 UTC; the server shows it in its configured time zone

        ClearLastError();
        if not TryStampRequisitionForm(Body, Stamped) then begin
            AddHeaderComment(PurchHeader, StrSubstNo(ReqFormSignFailedTxt, GetLastErrorText()));
            exit;
        end;

        Clear(TempBlob);
        TempBlob.CreateOutStream(OutStr);
        Base64Convert.FromBase64(Stamped, OutStr);
        TempBlob.CreateInStream(InStr);
        DocAtt."Document Reference ID".ImportStream(InStr, DocAtt."File Name");
        DocAtt.Modify(true);
    end;

    [TryFunction]
    local procedure TryStampRequisitionForm(Body: JsonObject; var Stamped: Text)
    begin
        // HTTP only - no database writes in here
        Stamped := GetText(PostJson('/api/reqform/stamp', Body), 'pdfBase64');
        if Stamped = '' then
            Error('The OCR server returned no PDF.');
    end;

    local procedure GLStringOf(StmtLine: Record "MID Card Stmt Line") GL: Text
    begin
        // account-dimension1-dimension2, as entered in the portal
        GL := StmtLine."G/L Account No.";
        if StmtLine."Dimension 1 Code" <> '' then
            GL += '-' + StmtLine."Dimension 1 Code";
        if StmtLine."Dimension 2 Code" <> '' then
            GL += '-' + StmtLine."Dimension 2 Code";
    end;

    local procedure AddHeaderComment(PurchHeader: Record "Purchase Header"; CommentText: Text)
    var
        Comment: Record "Purch. Comment Line";
        LineNo: Integer;
    begin
        Comment.SetRange("Document Type", PurchHeader."Document Type");
        Comment.SetRange("No.", PurchHeader."No.");
        Comment.SetRange("Document Line No.", 0);
        if Comment.FindLast() then
            LineNo := Comment."Line No.";
        while CommentText <> '' do begin
            LineNo += 10000;
            Comment.Init();
            Comment."Document Type" := PurchHeader."Document Type";
            Comment."No." := PurchHeader."No.";
            Comment."Document Line No." := 0;
            Comment."Line No." := LineNo;
            Comment.Date := Today();
            Comment.Comment := CopyStr(CommentText, 1, MaxStrLen(Comment.Comment));
            Comment.Insert(true);
            CommentText := CopyStr(CommentText, MaxStrLen(Comment.Comment) + 1);
        end;
    end;

    // Returns notes about any coding that didn't match BC (those fields are left blank).
    local procedure CreatePurchLine(PurchHeader: Record "Purchase Header"; StmtLine: Record "MID Card Stmt Line"; LineNo: Integer) Notes: Text
    var
        PurchLine: Record "Purchase Line";
        GLSetup: Record "General Ledger Setup";
        Qty: Decimal;
    begin
        GLSetup.Get();
        Qty := 1;
        if StmtLine.Amount < 0 then
            Qty := -1;                                                                 // credit / refund

        PurchLine.Init();
        PurchLine."Document Type" := PurchHeader."Document Type";
        PurchLine."Document No." := PurchHeader."No.";
        PurchLine."Line No." := LineNo;
        PurchLine.Insert(true);

        PurchLine.Validate(Type, PurchLine.Type::"G/L Account");
        if IsValidGLAccount(StmtLine."G/L Account No.") then
            PurchLine.Validate("No.", StmtLine."G/L Account No.")
        else
            AddNote(Notes, StrSubstNo(GLNotFoundTxt, StmtLine."G/L Account No.", Format(Abs(StmtLine.Amount), 0, '<Precision,2:2><Standard Format,0>')));

        PurchLine.Description := CopyStr(Format(StmtLine."Transaction Date", 0, '<Month,2>/<Day,2>') + ' ' + StmtLine.Description,
                                         1, MaxStrLen(PurchLine.Description));
        PurchLine."Description 2" := CopyStr('Ref ' + StmtLine.Reference, 1, MaxStrLen(PurchLine."Description 2"));

        if PurchLine."No." <> '' then begin
            PurchLine.Validate(Quantity, Qty);
            PurchLine.Validate("Direct Unit Cost", Abs(StmtLine.Amount));
        end else
            if not TrySetQtyAndCost(PurchLine, Qty, Abs(StmtLine.Amount)) then begin
                // no account to calculate against: store the values so AP can see them
                PurchLine.Quantity := Qty;
                PurchLine."Direct Unit Cost" := Abs(StmtLine.Amount);
            end;

        if IsValidDimValue(GLSetup."Shortcut Dimension 1 Code", StmtLine."Dimension 1 Code") then
            PurchLine.Validate("Shortcut Dimension 1 Code", StmtLine."Dimension 1 Code")
        else
            if StmtLine."Dimension 1 Code" <> '' then
                AddNote(Notes, StrSubstNo(DimNotFoundTxt, GLSetup."Shortcut Dimension 1 Code", StmtLine."Dimension 1 Code"));
        if IsValidDimValue(GLSetup."Shortcut Dimension 2 Code", StmtLine."Dimension 2 Code") then
            PurchLine.Validate("Shortcut Dimension 2 Code", StmtLine."Dimension 2 Code")
        else
            if StmtLine."Dimension 2 Code" <> '' then
                AddNote(Notes, StrSubstNo(DimNotFoundTxt, GLSetup."Shortcut Dimension 2 Code", StmtLine."Dimension 2 Code"));

        PurchLine.Modify(true);
    end;

    [TryFunction]
    local procedure TrySetQtyAndCost(var PurchLine: Record "Purchase Line"; Qty: Decimal; Cost: Decimal)
    begin
        PurchLine.Validate(Quantity, Qty);
        PurchLine.Validate("Direct Unit Cost", Cost);
    end;

    local procedure IsValidGLAccount(AccountNo: Code[20]): Boolean
    var
        GLAccount: Record "G/L Account";
    begin
        if AccountNo = '' then
            exit(false);
        if not GLAccount.Get(AccountNo) then
            exit(false);
        exit((GLAccount."Account Type" = GLAccount."Account Type"::Posting) and GLAccount."Direct Posting" and not GLAccount.Blocked);
    end;

    local procedure IsValidDimValue(DimCode: Code[20]; ValueCode: Code[20]): Boolean
    var
        DimValue: Record "Dimension Value";
    begin
        if (DimCode = '') or (ValueCode = '') then
            exit(false);
        if not DimValue.Get(DimCode, ValueCode) then
            exit(false);
        exit((DimValue."Dimension Value Type" = DimValue."Dimension Value Type"::Standard) and not DimValue.Blocked);
    end;

    local procedure AddNote(var Notes: Text; Note: Text)
    begin
        if Notes <> '' then
            Notes += ' ';
        Notes += Note;
    end;

    local procedure AttachReceipt(PurchHeader: Record "Purchase Header"; var StmtLine: Record "MID Card Stmt Line"; LineNo: Integer)
    var
        DocAttachment: Record "Document Attachment";
        RecRef: RecordRef;
        InStr: InStream;
    begin
        StmtLine.CalcFields(Receipt);
        if not StmtLine.Receipt.HasValue() then
            exit;
        StmtLine.Receipt.CreateInStream(InStr);
        RecRef.GetTable(PurchHeader);
        // line no. in the name keeps names unique and ties the receipt to its invoice line
        DocAttachment.SaveAttachmentFromStream(InStr, RecRef,
            StrSubstNo('L%1 %2 %3', LineNo, Format(StmtLine."Transaction Date", 0, '<Month,2>-<Day,2>'), StmtLine."Receipt File Name"));
    end;

    local procedure AddReceiptComment(PurchHeader: Record "Purchase Header"; StmtLine: Record "MID Card Stmt Line"; LineNo: Integer; CodingNotes: Text)
    var
        Comment: Record "Purch. Comment Line";
        CommentText: Text;
        CommentLineNo: Integer;
    begin
        case StmtLine."Receipt Check" of
            'match':
                CommentText := '';
            'found':
                CommentText := 'Receipt: amount found but not on a total line.';
            'missing':
                CommentText := 'Receipt missing.';
            'date_mismatch':
                CommentText := StrSubstNo('Receipt date not within a few days of the charge. %1', StmtLine."Receipt Note");
            '':
                CommentText := 'No receipt (credit).';
            else
                CommentText := StrSubstNo('Receipt total did not match (%1). %2', StmtLine."Receipt Check", StmtLine."Receipt Note");
        end;
        if CodingNotes <> '' then
            CommentText := DelChr(CommentText + ' ' + CodingNotes, '<>', ' ');
        // comment lines are 80 chars; wrap long text
        while CommentText <> '' do begin
            CommentLineNo += 10000;
            Comment.Init();
            Comment."Document Type" := PurchHeader."Document Type";
            Comment."No." := PurchHeader."No.";
            Comment."Document Line No." := LineNo;
            Comment."Line No." := CommentLineNo;
            Comment.Date := Today();
            Comment.Comment := CopyStr(CommentText, 1, MaxStrLen(Comment.Comment));
            Comment.Insert(true);
            CommentText := CopyStr(CommentText, MaxStrLen(Comment.Comment) + 1);
        end;
    end;

    local procedure GetNextLineNo(PurchHeader: Record "Purchase Header"): Integer
    var
        PurchLine: Record "Purchase Line";
    begin
        PurchLine.SetRange("Document Type", PurchHeader."Document Type");
        PurchLine.SetRange("Document No.", PurchHeader."No.");
        if PurchLine.FindLast() then
            exit(PurchLine."Line No." + 10000);
        exit(10000);
    end;

    local procedure MarkRequestSubmitted(Batch: Record "MID Card Stmt Batch")
    var
        Request: Record "MID Card Stmt Request";
    begin
        Request.SetCurrentKey(Token);
        Request.SetRange(Token, Batch."Assignment Token");
        if Request.FindFirst() then begin
            Request.Status := Request.Status::Submitted;
            Request."Submitted At" := Batch."Submitted At";
            Request."Submitted By" := Batch."Submitted By";
            Request.Modify();
        end;
    end;

    // ================================================================ OCR server calls
    local procedure PostStatement(Merchant: Text; FileName: Text; InStr: InStream): JsonObject
    var
        Uri: Codeunit Uri;
        Content: HttpContent;
        Headers: HttpHeaders;
    begin
        Content.WriteFrom(InStr);
        Content.GetHeaders(Headers);
        if Headers.Contains('Content-Type') then
            Headers.Remove('Content-Type');
        Headers.Add('Content-Type', 'application/pdf');
        exit(CallApi('POST', '/api/statements?merchant=' + Merchant + '&filename=' + Uri.EscapeDataString(FileName), Content, true));
    end;

    local procedure PostAssignment(StatementId: Text; Last4: Text; PurchHeader: Record "Purchase Header"; ManagerEmail: Text; ManagerName: Text): JsonObject
    var
        Company: Record Company;
        UserRec: Record User;
        SenderEmail: Text;
        Body: JsonObject;
        Content: HttpContent;
        Headers: HttpHeaders;
        BodyText: Text;
    begin
        Company.Get(CompanyName());
        Body.Add('statementId', StatementId);
        Body.Add('last4', Last4);
        Body.Add('invoiceId', Format(PurchHeader.SystemId, 0, 4));
        Body.Add('invoiceNo', PurchHeader."No.");
        Body.Add('companyId', Format(Company.Id, 0, 4));
        Body.Add('managerEmail', ManagerEmail);
        Body.Add('managerName', ManagerName);
        // the server emails this person when the manager approves
        if UserRec.Get(UserSecurityId()) then
            if UserRec."Authentication Email" <> '' then
                SenderEmail := UserRec."Authentication Email"
            else
                SenderEmail := UserRec."Contact Email";
        Body.Add('senderEmail', SenderEmail);
        Body.WriteTo(BodyText);
        Content.WriteFrom(BodyText);
        Content.GetHeaders(Headers);
        if Headers.Contains('Content-Type') then
            Headers.Remove('Content-Type');
        Headers.Add('Content-Type', 'application/json');
        exit(CallApi('POST', '/api/assignments', Content, true));
    end;

    procedure TestConnection()
    var
        Content: HttpContent;
        Result: JsonObject;
        Tok, Item : JsonToken;
        Names: Text;
    begin
        Result := CallApi('GET', '/api/merchants', Content, false);
        Result.Get('items', Tok);
        foreach Item in Tok.AsArray() do
            Names += GetText(Item.AsObject(), 'label') + '  ';
        Message(ConnectionOkMsg, Names);
    end;

    local procedure CallApi(Method: Text; PathAndQuery: Text; Content: HttpContent; WithBody: Boolean) Result: JsonObject
    var
        Client: HttpClient;
        Request: HttpRequestMessage;
        Response: HttpResponseMessage;
        Headers: HttpHeaders;
        Body: Text;
        Arr: JsonArray;
    begin
        Request.Method(Method);
        Request.SetRequestUri(BaseUrl() + PathAndQuery);
        Request.GetHeaders(Headers);
        Headers.Add('X-API-Key', GetApiKey());
        if WithBody then
            Request.Content(Content);
        Client.Timeout(300000);   // OCR fallback on a scanned statement can take a while
        ClearLastError();
        if not TrySend(Client, Request, Response) then
            Error(CannotReachErr, BaseUrl(), GetLastErrorText());
        Response.Content().ReadAs(Body);
        if not Response.IsSuccessStatusCode() then
            Error(ApiErr, Response.HttpStatusCode(), ErrorDetail(Body));
        if Body.StartsWith('[') then begin    // list responses are wrapped so callers always get an object
            Arr.ReadFrom(Body);
            Result.Add('items', Arr);
        end else
            Result.ReadFrom(Body);
    end;

    // Without the return value, a failed Send raises the platform's real error
    // (DNS, TLS, refused, timeout, blocked by Extension Settings); the TryFunction
    // catches it so GetLastErrorText() holds that reason.
    [TryFunction]
    local procedure TrySend(var Client: HttpClient; var Request: HttpRequestMessage; var Response: HttpResponseMessage)
    begin
        Client.Send(Request, Response);
    end;

    local procedure ErrorDetail(Body: Text) Detail: Text
    var
        Obj: JsonObject;
        Tok: JsonToken;
    begin
        if Obj.ReadFrom(Body) then
            if Obj.Get('detail', Tok) then begin
                if Tok.IsValue() then
                    exit(Tok.AsValue().AsText());
                Tok.WriteTo(Detail);
                exit(Detail);
            end;
        exit(CopyStr(Body, 1, 500));
    end;

    // ================================================================ Send for Requisition Approval
    // Hands the request to the OCR server: it checks the invoice, creates the portal link and emails
    // the Requisition Manager. Returns '' when the email went out, otherwise the reason, so the
    // caller can undo what it saved (the uploaded vendor invoice and the blank Requisition Form).
    procedure SendRequisitionApproval(PurchHeader: Record "Purchase Header"; AttachmentId: Guid; AttachmentName: Text; ManagerEmail: Text; ManagerName: Text; CreatorEmail: Text): Text
    var
        Company: Record Company;
        Body, Result : JsonObject;
    begin
        Company.Get(CompanyName());
        Body.Add('invoiceId', Format(PurchHeader.SystemId, 0, 4));
        Body.Add('invoiceNo', PurchHeader."No.");
        Body.Add('companyId', Format(Company.Id, 0, 4));
        Body.Add('vendorNo', PurchHeader."Buy-from Vendor No.");
        Body.Add('vendorName', PurchHeader."Buy-from Vendor Name");
        Body.Add('vendorInvoiceNo', PurchHeader."Vendor Invoice No.");
        Body.Add('attachmentId', Format(AttachmentId, 0, 4));
        Body.Add('attachmentName', AttachmentName);
        Body.Add('managerEmail', ManagerEmail);
        Body.Add('managerName', ManagerName);
        Body.Add('creatorEmail', CreatorEmail);
        ClearLastError();
        if not TryPostJson('/api/reqapproval/send', Body, Result) then
            exit(GetLastErrorText());
        exit('');
    end;

    [TryFunction]
    local procedure TryPostJson(PathAndQuery: Text; Body: JsonObject; var Result: JsonObject)
    begin
        Result := PostJson(PathAndQuery, Body);
    end;

    local procedure BaseUrl(): Text
    var
        Setup: Record "MID Endpoint API";
        Host: Text;
    begin
        if not Setup.Get('SETUP') then
            Error(NoSetupErr);
        Host := DelChr(Setup."OCR Host", '<>', ' /');
        if Host = '' then
            Error(NoSetupErr);
        if Host.StartsWith('http') then
            exit(Host);
        exit('https://' + Host);
    end;

    local procedure GetText(Obj: JsonObject; KeyName: Text): Text
    var
        Tok: JsonToken;
    begin
        if Obj.Get(KeyName, Tok) then
            if Tok.IsValue() then
                if not Tok.AsValue().IsNull() then
                    exit(Tok.AsValue().AsText());
        exit('');
    end;

    // ================================================================ requisition form report (Report Selections, usage Requisition)
    procedure SetRequisitionFormReport(ReportId: Integer)
    var
        ReportSelections: Record "Report Selections";
    begin
        ReportSelections.SetRange(Usage, Enum::"Report Selection Usage"::Requisition);
        if ReportId = 0 then begin
            ReportSelections.DeleteAll(true);
            exit;
        end;
        if ReportSelections.FindFirst() then begin
            if ReportSelections."Report ID" <> ReportId then begin
                ReportSelections.Validate("Report ID", ReportId);
                ReportSelections.Modify(true);
            end;
            exit;
        end;
        ReportSelections.Init();
        ReportSelections.Validate(Usage, Enum::"Report Selection Usage"::Requisition);
        ReportSelections.Sequence := '1';
        ReportSelections.Validate("Report ID", ReportId);
        ReportSelections.Insert(true);
    end;

    // SaveAsDocumentAttachment names the file after the report, so the report id finds the form just attached
    procedure RequisitionFormFileFilter(): Text
    var
        ReportSelections: Record "Report Selections";
    begin
        ReportSelections.SetRange(Usage, Enum::"Report Selection Usage"::Requisition);
        if not ReportSelections.FindFirst() or (ReportSelections."Report ID" = 0) then
            Error(NoReqFormReportErr);
        exit('*' + Format(ReportSelections."Report ID") + '*');
    end;

    // ================================================================ API key (isolated storage, never in a table)
    local procedure GetApiKey() ApiKey: SecretText
    begin
        if not IsolatedStorage.Get(ApiKeyStorageTok, DataScope::Module, ApiKey) then
            Error(NoApiKeyErr);
    end;

    procedure SetApiKey(NewKey: Text)
    begin
        if NewKey = '' then
            IsolatedStorage.Delete(ApiKeyStorageTok, DataScope::Module)
        else
            IsolatedStorage.Set(ApiKeyStorageTok, NewKey, DataScope::Module);
    end;

    procedure HasApiKey(): Boolean
    begin
        exit(IsolatedStorage.Contains(ApiKeyStorageTok, DataScope::Module));
    end;
}
