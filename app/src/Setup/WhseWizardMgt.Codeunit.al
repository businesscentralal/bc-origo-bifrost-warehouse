namespace Origo.Bifrost.Warehouse;

using System.Environment.Configuration;

/// <summary>Reads Warehouse setup prerequisites and completes only on the explicit Finish command.</summary>
codeunit 10078386 "Whse Wizard Mgt ori"
{
    Access = Internal;
    Permissions = tabledata "NAV App Setting" = R;

    /// <summary>Reads only this application's HTTP setting without creating or changing it.</summary>
    internal procedure IsHttpEnabled(): Boolean
    var
        AppSetting: Record "NAV App Setting";
        AppInfo: ModuleInfo;
    begin
        if not AppSetting.ReadPermission() then
            exit(false);
        NavApp.GetCurrentModuleInfo(AppInfo);
        if not AppSetting.Get(AppInfo.Id()) then
            exit(false);
        exit(AppSetting."Allow HttpClient Requests");
    end;

    /// <summary>Reports whether the caller may change extension settings through Foundation.</summary>
    internal procedure CanEnableHttp(): Boolean
    var
        AppSetting: Record "NAV App Setting";
    begin
        exit(AppSetting.WritePermission());
    end;

    /// <summary>Returns the two assignable Warehouse permission sets; this procedure never assigns them.</summary>
    internal procedure GetPermissionSets(): List of [Code[20]]
    var
        PermissionSets: List of [Code[20]];
    begin
        PermissionSets.Add('BIFROST WhseInv ori');
        PermissionSets.Add('BIFROST WhsePost ori');
        exit(PermissionSets);
    end;

    /// <summary>Marks this assisted setup complete when the administrator explicitly finishes it.</summary>
    internal procedure Finish()
    var
        GuidedExperience: Codeunit "Guided Experience";
    begin
        GuidedExperience.CompleteAssistedSetup(ObjectType::Page, Page::"Whse Setup Wizard ori");
    end;
}
