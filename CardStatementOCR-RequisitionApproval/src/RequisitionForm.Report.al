// A generic Requisition Form for Card Statement OCR and Send for Requisition Approval.
// Company name, address and logo (Picture) come from Company Information. A wide logo that
// already shows the name fits the header; with no logo, the name is printed in its place.
// Set it on Endpoint API Setup (Requisition Form Report ID = 50120); it's printed through
// Report Selections (usage Requisition) and attached to the purchase invoice as the blank form.
//
// The OCR server signs the PDF by finding these labels on page 1 and writing on the underline to
// their right: "Description:", "G/L Account:", "Cost:", "Signed By:", "Approved By:".
// If you copy this layout to make your own, keep those labels as real text with an underline
// on the same row, and don't use them anywhere else on the page (docs/INSTALL.md, section 11.3).
report 50120 "MID Requisition Form"
{
    Caption = 'Requisition Form';
    ApplicationArea = All;
    UsageCategory = None;
    DefaultRenderingLayout = RequisitionFormRDLC;

    dataset
    {
        dataitem(PurchHeader; "Purchase Header")
        {
            RequestFilterFields = "Document Type", "No.";

            column(CompanyName; CompanyInfo.Name) { }
            column(CompanyAddress; CompanyAddressText) { }
            column(CompanyLogo; CompanyLogoBase64) { }   // base64 text, "" when there's no logo
            column(InvoiceNo; "No.") { }
            column(DocumentDate; FormatDate("Document Date")) { }
            column(DueDate; FormatDate("Due Date")) { }
            column(VendorName; "Buy-from Vendor Name") { }
            column(VendorNo; "Buy-from Vendor No.") { }
            column(VendorInvoiceNo; "Vendor Invoice No.") { }
            column(PreparedBy; PreparedBy) { }
        }
    }

    rendering
    {
        layout(RequisitionFormRDLC)
        {
            Type = RDLC;
            LayoutFile = 'src/layouts/RequisitionForm.rdlc';
            Caption = 'Requisition Form';
            Summary = 'One-page requisition form that the OCR server fills in and signs electronically.';
        }
    }

    trigger OnPreReport()
    var
        User: Record User;
        FormatAddress: Codeunit "Format Address";
        Base64Convert: Codeunit "Base64 Convert";
        LogoStream: InStream;
        Addr: array[8] of Text[100];
        i: Integer;
    begin
        CompanyInfo.Get();
        CompanyInfo.CalcFields(Picture);
        if CompanyInfo.Picture.HasValue() then begin
            CompanyInfo.Picture.CreateInStream(LogoStream);
            CompanyLogoBase64 := Base64Convert.ToBase64(LogoStream);
        end;
        FormatAddress.Company(Addr, CompanyInfo);
        for i := 2 to ArrayLen(Addr) do   // line 1 is the company name; the rest go on one line under the logo
            if Addr[i] <> '' then begin
                if CompanyAddressText <> '' then
                    CompanyAddressText += ', ';
                CompanyAddressText += Addr[i];
            end;

        // the email of the user who sends the invoice from BC (Card Statement OCR / Send for Requisition Approval)
        PreparedBy := UserId();
        if User.Get(UserSecurityId()) then
            if User."Authentication Email" <> '' then
                PreparedBy := User."Authentication Email"
            else
                if User."Contact Email" <> '' then
                    PreparedBy := User."Contact Email";
    end;

    var
        CompanyInfo: Record "Company Information";
        CompanyAddressText: Text;
        CompanyLogoBase64: Text;
        PreparedBy: Text;

    local procedure FormatDate(Value: Date): Text
    begin
        if Value = 0D then
            exit('');
        exit(Format(Value, 0, '<Month,2>/<Day,2>/<Year4>'));
    end;
}
