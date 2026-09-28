namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost.Warehouse;

/// <summary>
/// Restrictive permission set that can run Warehouse.Activity.Get without table read permission.
/// </summary>
permissionset 97010 "Whse No Read ori"
{
    Assignable = true;
    Caption = 'Whse Test No Read', MaxLength = 30;

    Permissions =
        codeunit "Whse Activity Get Impl ori" = X;
}
