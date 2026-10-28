namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;
using System.Environment.Configuration;
using System.Media;

/// <summary>Registers Warehouse assisted setup without changing any application settings.</summary>
codeunit 10078385 "Whse Wizard Reg. ori"
{
    Access = Internal;
    InherentPermissions = X;
    InherentEntitlements = X;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Guided Experience", OnRegisterAssistedSetup, '', false, false)]
    local procedure RegisterWizard()
    var
        GuidedExperience: Codeunit "Guided Experience";
        TitleLbl: Label 'Set up Bifrost Warehouse', Comment = 'is-IS=Setja upp Bifröst vöruhús';
        ShortTitleLbl: Label 'Bifrost Warehouse', Comment = 'is-IS=Bifröst vöruhús';
        DescriptionLbl: Label 'Learn what Warehouse adds to Bifrost, check HTTP through Bifrost Setup, and review user access.', Comment = 'is-IS=Kynntu þér hvað Vöruhús bætir við Bifröst, athugaðu HTTP í Bifröst uppsetningu og farðu yfir aðgang notenda.';
    begin
        GuidedExperience.InsertAssistedSetup(TitleLbl, ShortTitleLbl, DescriptionLbl, 5,
            ObjectType::Page, Page::"Whse Setup Wizard ori", Enum::"Assisted Setup Group"::Extensions,
            '', Enum::"Video Category"::Uncategorized, 'https://docs.bifrost.origo.is/en-us/warehouse/');
    end;
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"App Registry ori", OnRegisterApps, '', false, false)]
    local procedure RegisterWarehouseApp(var Apps: Record "Registered App ori" temporary)
    var
        AppRegistry: Codeunit "App Registry ori";
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        AppRegistry.AddApp(Apps, AppInfo.Id(), CopyStr(AppInfo.Name(), 1, MaxStrLen(Apps."App Name")), Page::"Whse Setup Wizard ori");
    end;
}
