namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Covers the registration of Bifrost Warehouse in the Bifröst Foundation application registry.
/// Setup notifications live on the Bifröst Setup page only, so Foundation has to find this
/// application - and its setup page - through <c>App Registry ori</c>.
/// </summary>
codeunit 97005 "Whse Registration Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit Assert;
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        if IsInitialized then
            exit;
        IsInitialized := true;
    end;

    /// <summary>Opens Foundation setup with Warehouse installed and only the licence-admin role in English.</summary>
    [Test]
    procedure Scenario_AC03_LicenceAdmin_OpensSetupInEnglish()
    begin
        // Story #90 AC03 | Time: independent of Today/WorkDate | Risk: cross-app registration execute permission.
        AssertLicenceAdminOpensSetup(1033);
    end;

    /// <summary>Proves the same restricted setup path in Icelandic without granting Warehouse administration.</summary>
    [Test]
    procedure Scenario_AC03_LicenceAdmin_OpensSetupInIcelandic()
    begin
        // Story #90 AC03 | Time: independent of Today/WorkDate | Risk: cross-app registration execute permission.
        AssertLicenceAdminOpensSetup(1039);
    end;

    local procedure AssertLicenceAdminOpensSetup(LanguageId: Integer)
    var
        BifrostSetup: Record "Setup ori";
        TempRegisteredApp: Record "Registered App ori" temporary;
        AppRegistry: Codeunit "App Registry ori";
        LowerPermissions: Codeunit "Library - Lower Permissions";
        SetupPage: TestPage "Setup ori";
        PreviousLanguage: Integer;
        RegisteredSetupPageId: Integer;
        IsEditable: Boolean;
        CanWriteSetup: Boolean;
        IsRegistered: Boolean;
        PermissionsLowered: Boolean;
        WarehouseAppId: Guid;
    begin
        // [GIVEN] Our installed app and Foundation setup; no consent, trial, quota or licence state changes.
        Initialize();
        // Foundation's public initialization API; no direct Setup table read or permission grant.
        BifrostSetup.InsertIfNotExists();
        WarehouseAppId := '47acac54-3873-496f-9e88-157f36413e89';
        PreviousLanguage := GlobalLanguage();
        GlobalLanguage(LanguageId);

        LowerPermissions.StartLoggingNAVPermissions();
        LowerPermissions.SetExactPermissionSet('BIFROST LicAdm ori');
        // Platform baseline only: no Warehouse codeunit grant, SUPER, or BIFROST Full.
        LowerPermissions.AddPermissionSet('Whse Test Plat ori');
        PermissionsLowered := LowerPermissions.HasChangedPermissions();
        CanWriteSetup := BifrostSetup.WritePermission();

        // [WHEN] The real page-open path raises OnRegisterApps under the restricted role.
        SetupPage.OpenView();
        IsEditable := SetupPage.Editable();
        SetupPage.Close();
        AppRegistry.GetApps(TempRegisteredApp);
        IsRegistered := TempRegisteredApp.Get(WarehouseAppId);
        RegisteredSetupPageId := TempRegisteredApp."Setup Page Id";

        // [THEN] Assertions run outside the restricted role; the product calls above do not.
        LowerPermissions.StopLoggingNAVPermissions();
        GlobalLanguage(PreviousLanguage);
        Assert.IsTrue(PermissionsLowered, 'The permission mock must be active for this regression.');
        Assert.IsFalse(CanWriteSetup, 'The licence administrator must not gain direct setup write permission.');
        Assert.IsFalse(IsEditable, 'Bifrost setup must remain read-only for a licence administrator.');
        Assert.IsTrue(IsRegistered, 'Warehouse must register under the restricted licence-admin role.');
        Assert.AreEqual(Page::"Whse Setup Wizard ori", RegisteredSetupPageId, 'The restricted registry must retain the Warehouse setup page.');
    end;

    [Test]
    procedure Scenario_AC02_Registry_ContainsWarehouseWizard()
    var
        TempRegisteredApp: Record "Registered App ori" temporary;
        AppRegistry: Codeunit "App Registry ori";
    begin
        // Story #90 AC02 | Time: independent of Today/WorkDate | Risk: registry identity and setup mapping.
        // [SCENARIO] Bifrost Warehouse raises no setup notification of its own; Foundation
        // aggregates them on Bifröst Setup and finds this application through the registry

        // [GIVEN] the installed application
        Initialize();

        // [WHEN] the registry is built
        AppRegistry.GetApps(TempRegisteredApp);

        // [THEN] Bifrost Warehouse is in it, under its own module id
        Assert.IsTrue(TempRegisteredApp.Get('47acac54-3873-496f-9e88-157f36413e89'), 'Bifrost Warehouse must register itself in the Bifrost application registry');
        Assert.AreNotEqual('', TempRegisteredApp."App Name", 'A registered application must carry a name');

        // [THEN] and it points at its own setup page, not at the Bifröst Setup page
        Assert.AreEqual(Page::"Whse Setup Wizard ori", TempRegisteredApp."Setup Page Id", 'The registry must point at the Bifrost Warehouse setup page');
        Assert.AreNotEqual(AppRegistry.GetFoundationAppId(), TempRegisteredApp."App Id", 'Bifrost Warehouse must register under its own module id, not under the Foundation one');
    end;
}
