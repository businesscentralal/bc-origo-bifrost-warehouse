namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Permission token for BIFROST WhsePost ori.
/// No records are stored. WritePermission() on this table is the warehouse posting gate.
/// </summary>
table 10078452 "Whse Posting ori"
{
    Extensible = false;
    Access = Internal;
    Caption = 'BIFROST WhsePost ori', Comment = 'is-IS=Bifröst bókun vörugeymslu';
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
