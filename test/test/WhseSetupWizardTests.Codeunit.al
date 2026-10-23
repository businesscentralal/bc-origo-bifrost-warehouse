namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.Environment.Configuration;
using System.Security.AccessControl;
using System.TestLibraries.Utilities;

/// <summary>Issue #83: verifies the assisted setup lifecycle and read-only HTTP and access guidance.</summary>
codeunit 97003 "Whse Setup Wizard Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>AC01: the real registration event creates an incomplete Warehouse assisted setup.</summary>
    [Test]
    procedure AC01_RegistrationCreatesIncompleteSetup()
    var
        Assert: Codeunit "Library Assert";
        GuidedExperience: Codeunit "Guided Experience";
    begin
        // [GIVEN] This application's assisted setup has no previous completion.
        RegisterWizard();
        // [WHEN] The platform inspects assisted setups registered for the Warehouse extension.
        // [THEN] Registration exists and does not complete the setup.
        Assert.IsTrue(GuidedExperience.Exists(Enum::"Guided Experience Type"::"Assisted Setup", ObjectType::Page, Page::"Whse Setup Wizard ori"), 'Warehouse assisted setup must be registered.');
        Assert.IsFalse(GuidedExperience.IsAssistedSetupComplete(ObjectType::Page, Page::"Whse Setup Wizard ori"), 'Registration must leave the setup incomplete.');
    end;

    /// <summary>AC03: the status reader reflects this application's actual setting, with no test write.</summary>
    [Test]
    procedure AC03_HttpStatusReadsWarehouseOnly()
    var
        AppSetting: Record "NAV App Setting";
        Assert: Codeunit "Library Assert";
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        ExpectedEnabled: Boolean;
        WarehouseAppId: Guid;
    begin
        // [GIVEN] The current platform setting; fixtures never create or modify it.
        WarehouseAppId := '47acac54-3873-496f-9e88-157f36413e89';
        if AppSetting.Get(WarehouseAppId) then
            ExpectedEnabled := AppSetting."Allow HttpClient Requests"
        else
            ExpectedEnabled := false;
        // [WHEN] Warehouse reads its status.
        // [THEN] The actual owning application setting is used.
        Assert.AreEqual(ExpectedEnabled, WizardMgt.IsHttpEnabled(), 'HTTP status must match Warehouse rather than the test app or Foundation.');
        Assert.AreEqual(AppSetting.WritePermission(), WizardMgt.CanEnableHttp(), 'The wizard must report the actual platform settings permission.');
    end;

    /// <summary>AC04: access guidance lists exactly the two installed assignable Warehouse sets.</summary>
    [Test]
    procedure AC04_PermissionSetsMatchInstalledMetadata()
    var
        PermissionSet: Record "Aggregate Permission Set";
        Assert: Codeunit "Library Assert";
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        PermissionSets: List of [Code[20]];
        RoleId: Code[20];
        WarehouseAppId: Guid;
    begin
        // [GIVEN] Warehouse's installed permission-set metadata.
        WarehouseAppId := '47acac54-3873-496f-9e88-157f36413e89';
        PermissionSet.SetRange("App ID", WarehouseAppId);
        PermissionSet.SetRange(Scope, PermissionSet.Scope::System);
        // [WHEN] The wizard supplies its access guidance.
        PermissionSets := WizardMgt.GetPermissionSets();
        // [THEN] Every actual assignable set is listed exactly once; no Foundation grants are assigned here.
        Assert.AreEqual(2, PermissionSets.Count(), 'Only the two Warehouse gates are assignable sets.');
        Assert.AreEqual(PermissionSet.Count(), PermissionSets.Count(), 'The list must match installed assignable permission sets.');
        foreach RoleId in PermissionSets do begin
            PermissionSet.SetRange("Role ID", RoleId);
            Assert.IsFalse(PermissionSet.IsEmpty(), 'The described set must belong to the Warehouse app: ' + RoleId);
        end;
    end;

    /// <summary>AC03 invalid input: the displayed HTTP state cannot be edited and does not persist a setting.</summary>
    [Test]
    procedure AC03_HttpStatusIsReadOnly()
    var
        Assert: Codeunit "Library Assert";
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        Wizard: TestPage "Whse Setup Wizard ori";
        PreviousHttpEnabled: Boolean;
    begin
        // [GIVEN] The platform HTTP setting and the wizard's read-only status field.
        PreviousHttpEnabled := WizardMgt.IsHttpEnabled();
        Wizard.OpenView();
        Wizard.Next.Invoke();
        // [WHEN] A caller attempts to edit the status control.
        asserterror Wizard.HttpEnabled.SetValue(not PreviousHttpEnabled);
        Wizard.Close();
        // [THEN] The platform setting remains unchanged; no fixture writes NAV App Setting.
        Assert.AreEqual(PreviousHttpEnabled, WizardMgt.IsHttpEnabled(), 'The read-only HTTP display must not change extension settings.');
    end;

    /// <summary>AC05: a complete page click-through marks assisted setup complete only on Finish.</summary>
    [Test]
    procedure AC05_FinishCompletesSetup()
    var
        Assert: Codeunit "Library Assert";
        GuidedExperience: Codeunit "Guided Experience";
        Wizard: TestPage "Whse Setup Wizard ori";
    begin
        // [GIVEN] A newly registered incomplete wizard.
        RegisterWizard();
        Wizard.OpenView();
        // [WHEN] The user visits each step and chooses Finish.
        Wizard.Next.Invoke();
        Wizard.Next.Invoke();
        Wizard.Next.Invoke();
        Assert.IsFalse(GuidedExperience.IsAssistedSetupComplete(ObjectType::Page, Page::"Whse Setup Wizard ori"), 'Visiting the summary is not completion.');
        Wizard.Finish.Invoke();
        // [THEN] Only the explicit Finish command completes setup.
        Assert.IsTrue(GuidedExperience.IsAssistedSetupComplete(ObjectType::Page, Page::"Whse Setup Wizard ori"), 'Finish must complete Warehouse assisted setup.');
    end;

    /// <summary>AC05: cancelling after navigating backward does not complete the setup or change HTTP.</summary>
    [Test]
    procedure AC05_EarlyCloseLeavesSetupIncomplete()
    var
        Assert: Codeunit "Library Assert";
        GuidedExperience: Codeunit "Guided Experience";
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        Wizard: TestPage "Whse Setup Wizard ori";
        PreviousHttpEnabled: Boolean;
    begin
        // [GIVEN] The existing HTTP setting and an incomplete wizard.
        RegisterWizard();
        PreviousHttpEnabled := WizardMgt.IsHttpEnabled();
        Wizard.OpenView();
        // [WHEN] The user visits HTTP, verifies, navigates back and closes early.
        Wizard.Next.Invoke();
        Wizard.Verify.Invoke();
        Wizard.Back.Invoke();
        Wizard.Close();
        // [THEN] Neither completion nor HTTP is changed.
        Assert.IsFalse(GuidedExperience.IsAssistedSetupComplete(ObjectType::Page, Page::"Whse Setup Wizard ori"), 'An early close must leave assisted setup incomplete.');
        Assert.AreEqual(PreviousHttpEnabled, WizardMgt.IsHttpEnabled(), 'Opening, verifying and cancelling must not change HTTP.');
    end;

    /// <summary>AC05 edge: rerunning and cancelling a completed wizard preserves its completed state.</summary>
    [Test]
    procedure AC05_ReopenPreservesPreviousCompletion()
    var
        Assert: Codeunit "Library Assert";
        GuidedExperience: Codeunit "Guided Experience";
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        Wizard: TestPage "Whse Setup Wizard ori";
    begin
        // [GIVEN] A previously completed setup.
        RegisterWizard();
        WizardMgt.Finish();
        // [WHEN] The administrator reopens and closes it.
        Wizard.OpenView();
        Wizard.Close();
        // [THEN] Reopening never resets a previous completion.
        Assert.IsTrue(GuidedExperience.IsAssistedSetupComplete(ObjectType::Page, Page::"Whse Setup Wizard ori"), 'A repeat visit must preserve existing completion.');
    end;

    /// <summary>AC01: the registered item is visible in the platform Extensions group.</summary>
    [Test]
    [HandlerFunctions('AssistedSetupHandler')]
    procedure AC01_RegistrationIsInExtensionsGroup()
    var
        GuidedExperience: Codeunit "Guided Experience";
    begin
        RegisterWizard();
        GuidedExperience.OpenAssistedSetup(Enum::"Assisted Setup Group"::Extensions);
    end;

    /// <summary>Checks the actual platform page after it filters the Extensions group.</summary>
    [PageHandler]
    procedure AssistedSetupHandler(var AssistedSetup: TestPage "Assisted Setup")
    var
        Assert: Codeunit "Library Assert";
    begin
        AssistedSetup.Filter.SetFilter(Title, 'Set up Bifrost Warehouse');
        Assert.IsTrue(AssistedSetup.First(), 'Warehouse must be listed in Extensions.');
        AssistedSetup.Completed.AssertEquals(false);
    end;

    /// <summary>AC02: the operations action opens the Foundation operations page.</summary>
    [Test]
    [HandlerFunctions('OperationsHandler')]
    procedure AC02_ShowOperationsOpensFoundationList()
    var
        Wizard: TestPage "Whse Setup Wizard ori";
    begin
        RegisterWizard();
        Wizard.OpenView();
        Wizard.ShowOperations.Invoke();
        Wizard.Close();
    end;

    /// <summary>Receives the actual operations page opened by the wizard action.</summary>
    [ModalPageHandler]
    procedure OperationsHandler(var Operations: TestPage "Message Type List ori")
    var
        Assert: Codeunit "Library Assert";
    begin
        Assert.IsTrue(Operations.First(), 'Installed Bifrost operations must be shown.');
    end;

    local procedure RegisterWizard()
    var
        Assert: Codeunit "Library Assert";
        GuidedExperience: Codeunit "Guided Experience";
        WarehouseAppId: Guid;
    begin
        // Story #83 | Time: independent of Today/WorkDate | Risk: own assisted setup only; no HTTP, consent or licensing writes.
        WarehouseAppId := '47acac54-3873-496f-9e88-157f36413e89';
        GuidedExperience.Remove(Enum::"Guided Experience Type"::"Assisted Setup", ObjectType::Page, Page::"Whse Setup Wizard ori");
        Assert.IsTrue(GuidedExperience.SetupForExtensionExists(WarehouseAppId), 'The platform event must register Warehouse setup.');
    end;
}
