namespace Origo.Bifrost.Warehouse;

using System.Upgrade;

/// <summary>
/// Upgrade entry point for Bifrost Warehouse. Ensures the initial-release tag is present.
/// </summary>
codeunit 10036943 "Warehouse Upgrade ori"
{
    Subtype = Upgrade;
    Access = Internal;

    trigger OnUpgradePerCompany()
    var
        UpgradeTag: Codeunit "Upgrade Tag";
        WarehouseInstall: Codeunit "Warehouse Install ori";
    begin
        if not UpgradeTag.HasUpgradeTag(WarehouseInstall.GetInitialReleaseTag()) then
            UpgradeTag.SetUpgradeTag(WarehouseInstall.GetInitialReleaseTag());
    end;
}