permissionset 50104 "MID INV PROCESSING"
{
    Assignable = true;
    IncludedPermissionSets = "D365 BASIC", "D365 READ";
    Permissions =
        tabledata "Purchase Header" = RIMD,
        tabledata "Purchase Line" = RIMD,
        tabledata "Incoming Document" = RIMD;
}

permissionset 50102 "MID REQ MGR"
{
    Caption = 'Requisition Manager Permissions';
    Permissions =
        tabledata "MID Requisition Manager" = RIMD; // R = Read, I = Insert, M = Modify, D = Delete
}

permissionset 50103 "MID ENDPOINT SETUP"
{
    Assignable = true; // so you can assign it to users
    Caption = 'Endpoint API setup access';

    // Grant data + object permissions for your new table and its setup page
    Permissions =
        tabledata "MID Endpoint API" = RIMD,  // Read/Insert/Modify/Delete data
        table "MID Endpoint API" = X,     // Execute object (metadata)
        page "MID Endpoint API Setup" = X;

    // Optional: if your actions run from Purchase Invoice and you want to be explicit:
    // page "Purchase Invoice" = X;
}
