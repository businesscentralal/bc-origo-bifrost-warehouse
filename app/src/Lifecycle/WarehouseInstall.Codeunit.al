namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;
using System.Upgrade;

/// <summary>
/// Fresh-install entry point for Bifrost Warehouse. Registers the initial release upgrade tag.
/// </summary>
codeunit 10036942 "Warehouse Install ori"
{
    Subtype = Install;
    Access = Internal;

    trigger OnInstallAppPerCompany()
    begin
        SetUpgradeTags();
    end;

    local procedure SetUpgradeTags()
    var
        UpgradeTag: Codeunit "Upgrade Tag";
    begin
        if not UpgradeTag.HasUpgradeTag(GetInitialReleaseTag()) then
            UpgradeTag.SetUpgradeTag(GetInitialReleaseTag());
    end;

    /// <summary>Returns the per-company initial-release upgrade tag.</summary>
    /// <returns>The initial-release upgrade tag.</returns>
    procedure GetInitialReleaseTag(): Code[250]
    begin
        exit('Origo.Bifrost.Warehouse-Initial-20260927');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Upgrade Tag", OnGetPerCompanyUpgradeTags, '', false, false)]
    local procedure RegisterPerCompanyTags(var PerCompanyUpgradeTags: List of [Code[250]])
    begin
        PerCompanyUpgradeTags.Add(GetInitialReleaseTag());
    end;
}