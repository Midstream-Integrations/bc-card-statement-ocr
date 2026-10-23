table 50102 "MID Requisition Manager"
{
    DataClassification = ToBeClassified;

    fields
    {
        field(1; "ID"; Integer)
        {
            DataClassification = SystemMetadata;
            AutoIncrement = true;
        }
        field(2; "Name"; Text[100])
        {
            DataClassification = CustomerContent;
        }
        field(3; "Email"; Text[100])
        {
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        key(PK; "ID")
        {
            Clustered = true;
        }
    }
}

page 50102 "MID Requisition Managers"
{
    PageType = List;
    SourceTable = "MID Requisition Manager";
    ApplicationArea = All;
    UsageCategory = Lists;
    Editable = true;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("Name"; Rec.Name)
                {
                    ApplicationArea = All;
                }
                field("Email"; Rec.Email)
                {
                    ApplicationArea = All;
                }
            }
        }
    }
}
