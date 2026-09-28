namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost.Warehouse;

/// <summary>
/// Restrictive permission set that can run the warehouse Get implementations without table read permission.
/// </summary>
permissionset 97010 "Whse NoRead Test ori"
{
    Assignable = true;
    Caption = 'Whse Test No Read', MaxLength = 30;

    Permissions =
        codeunit "Whse Activity Get Impl ori" = X,
        codeunit "Whse BinContent Get Impl ori" = X;
}
