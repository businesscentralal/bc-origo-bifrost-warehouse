namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Permission token for BIFROST WhseInv ori.
/// No records are stored. WritePermission() on this table is the invoice check for
/// Warehouse.Shipment.Post when invoice is true. It replaces Foundation's G/L posting
/// gate for that path, because this app does not call Foundation's posting gate.
/// </summary>
table 10078456 "Whse Invoice ori"
{
    Extensible = false;
    Access = Internal;
    Caption = 'BIFROST WhseInv ori', Comment = 'is-IS=Bifröst reikningsbókun vörugeymslu';
    DataClassification = SystemMetadata;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key', Comment = 'is-IS=Aðallykill';
            DataClassification = SystemMetadata;
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
