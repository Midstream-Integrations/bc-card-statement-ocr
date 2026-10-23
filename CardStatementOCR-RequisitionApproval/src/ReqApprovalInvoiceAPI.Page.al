page 50101 "MID Req. Approval Invoice API"
{
    PageType = API;
    DelayedInsert = true;
    SourceTable = "Purchase Header";
    SourceTableView = WHERE("Document Type" = CONST(Invoice));
    APIPublisher = 'midstream';
    APIGroup = 'RequisitionApprovalInvoices';
    APIVersion = 'v1.0';
    EntityName = 'RequisitionApprovalInvoices';
    EntitySetName = 'RequisitionApprovalInvoices';
    ODataKeyFields = SystemId;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(InvoiceNo; Rec."No.") { }
                field(VendorNo; Rec."Buy-from Vendor No.") { }
                field(VendorName; Rec."Buy-from Vendor Name") { }
                field(VendorInvoiceNo; Rec."Vendor Invoice No.") { }
                field(Guid; Rec.SystemId) { }
                // ... add more standard fields as needed

                field(mgrRequisitionApproval; Rec.mgrRequisitionApproval) { }
                field(HigherRequisitionApproval; Rec.HigherRequisitionApproval) { }
                field(HigherRequisitionEmail; Rec.HigherRequisitionEmail) { }
                field(HigherRequisitionName; Rec.HigherRequisitionName) { }
                field(RequisitionCreatorName; Rec.RequisitionCreatorName) { }
                field(RequisitionCreatorEmail; Rec.RequisitionCreatorEmail) { }

            }
        }
    }
}