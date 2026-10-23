namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost.Warehouse;
using System.Environment.Configuration;
using System.TestLibraries.Utilities;

/// <summary>Verifies setup HTTP reads and administrator guidance with indirect read and no settings write access.</summary>
codeunit 97004 "Whse Wizard Permission Tests"
{
    Subtype = Test;
    TestPermissions = Restrictive;

    /// <summary>AC03: an indirect-read user sees the real HTTP state without receiving write access.</summary>
    [Test]
    procedure AC03_IndirectReadReportsActualHttpState()
    var
        AppSetting: Record "NAV App Setting";
        Assert: Codeunit "Library Assert";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        ExpectedEnabled: Boolean;
    begin
        // Story #83, AC03 | Time: independent of Today/WorkDate | Risk: read-only system setting; no fixture writes.
        // [GIVEN] The actual owning app setting, read before restricting the caller.
        if AppSetting.Get('47acac54-3873-496f-9e88-157f36413e89') then
            ExpectedEnabled := AppSetting."Allow HttpClient Requests";
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse Wizard Test ori');
        Assert.IsFalse(AppSetting.WritePermission(), 'The caller must not have settings write access.');
        // [WHEN] The management codeunit reads with its explicit system-table read permission.
        // [THEN] The status matches the actual setting and write access remains denied.
        Assert.AreEqual(ExpectedEnabled, WizardMgt.IsHttpEnabled(), 'Indirect-read user must see the actual Warehouse HTTP state.');
        Assert.IsFalse(WizardMgt.CanEnableHttp(), 'The read grant must not enable settings writes.');
    end;

    /// <summary>AC03: restricted callers see administrator guidance and a read-only actual HTTP status.</summary>
    [Test]
    procedure AC03_NoWriteShowsAdministratorNote()
    var
        AppSetting: Record "NAV App Setting";
        Assert: Codeunit "Library Assert";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        Wizard: TestPage "Whse Setup Wizard ori";
        ExpectedEnabled: Boolean;
    begin
        // Story #83, AC03 | Time: independent of Today/WorkDate | Risk: no setup, HTTP or permission-assignment writes.
        // [GIVEN] An indirect-read caller without permission to change extension settings.
        if AppSetting.Get('47acac54-3873-496f-9e88-157f36413e89') then
            ExpectedEnabled := AppSetting."Allow HttpClient Requests";
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse Wizard Test ori');
        Assert.IsFalse(AppSetting.WritePermission(), 'The caller must not have settings write access.');
        // [WHEN] The user navigates to the HTTP step.
        Wizard.OpenView();
        Wizard.Next.Invoke();
        // [THEN] The actual status stays read-only and administrator guidance is visible.
        Wizard.HttpEnabled.AssertEquals(ExpectedEnabled);
        Assert.IsFalse(Wizard.HttpEnabled.Editable(), 'HTTP status must remain read-only.');
        Assert.IsTrue(Wizard.HttpPermissionNote.Visible(), 'A caller without settings write permission needs administrator guidance.');
        Wizard.Close();
    end;
}
