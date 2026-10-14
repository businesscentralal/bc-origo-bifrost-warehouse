namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse's registration through Foundation's existing take-over test harness.
/// The harness runs the real engine twice without exposing its internal production procedures.
/// </summary>
codeunit 97035 "Whse PermSet Pair Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>Checks a company-scoped legacy assignment migrates under Warehouse's App ID.</summary>
    [Test]
    procedure Scenario_AC02_CompanyAssignment_UsesWarehouseAppId()
    begin
        // Story #9, AC02 | Time: no date dependency | Risk: Foundation registration ownership.
        VerifyMigration('W2-WH9-COMPANY');
    end;

    /// <summary>Checks an all-company legacy assignment keeps its scope and Warehouse ownership.</summary>
    [Test]
    procedure Scenario_AC02_AllCompanies_UsesWarehouseAppId()
    begin
        // Story #9, AC02 | Time: no date dependency | Risk: all-company assignment scope.
        VerifyMigration('');
    end;

    local procedure VerifyMigration(FixtureCompany: Text[30])
    var
        Assert: Codeunit "Library Assert";
        TakeOverTests: Codeunit "TakeOver Tests";
        AccessControl: RecordRef;
        FixtureUserId: Guid;
        LegacyAppId: Guid;
        WarehouseAppId: Guid;
    begin
        // [SCENARIO] The automatically bound Warehouse subscriber adds its own permission set.
        FixtureUserId := UserSecurityId();
        LegacyAppId := 'a629b897-7541-4562-bebb-c6122f15801c';
        WarehouseAppId := '47acac54-3873-496f-9e88-157f36413e89';

        // [GIVEN] Isolated legacy data, with no existing target assignment to make the test pass.
        AccessControl.Open(2000000053);
        SetKey(AccessControl, FixtureUserId, 'CE Whse Post ori', FixtureCompany, LegacyAppId);
        Assert.IsFalse(AccessControl.Find('='), 'The legacy fixture key must be unused.');
        SetKey(AccessControl, FixtureUserId, 'BIFROST WhsePost ori', FixtureCompany, WarehouseAppId);
        Assert.IsFalse(AccessControl.Find('='), 'The Warehouse target must not exist before take-over.');
        SetKey(AccessControl, FixtureUserId, 'CE Whse Post ori', FixtureCompany, LegacyAppId);
        AccessControl.Insert(false);

        // [WHEN] The existing Foundation test harness runs the actual engine and checks idempotence.
        TakeOverTests.RunTakeOver_RunTwice_SecondRunCopiesNothing();

        // [THEN] The assignment keeps its company and is granted under Warehouse, never Foundation.
        SetKey(AccessControl, FixtureUserId, 'BIFROST WhsePost ori', FixtureCompany, WarehouseAppId);
        Assert.IsTrue(AccessControl.Find('='), 'The target must be granted under Warehouse''s App ID.');
        AccessControl.Delete(false);
        SetKey(AccessControl, FixtureUserId, 'BIFROST WhsePost ori', FixtureCompany, LegacyAppId);
        Assert.IsFalse(AccessControl.Find('='), 'The target must not retain the legacy App ID.');
        SetKey(AccessControl, FixtureUserId, 'BIFROST WhsePost ori', FixtureCompany, '7505e808-6e52-4b96-a328-82573391297a');
        Assert.IsFalse(AccessControl.Find('='), 'The target must not be granted under Foundation.');
        SetKey(AccessControl, FixtureUserId, 'CE Whse Post ori', FixtureCompany, LegacyAppId);
        Assert.IsTrue(AccessControl.Find('='), 'Take-over must preserve the original legacy assignment.');
        AccessControl.Delete(false);
        AccessControl.Close();
    end;

    local procedure SetKey(var AccessControl: RecordRef; FixtureUserId: Guid; RoleId: Code[20]; FixtureCompany: Text[30]; AppId: Guid)
    begin
        AccessControl.Init();
        AccessControl.Field(1).Value := FixtureUserId;
        AccessControl.Field(2).Value := RoleId;
        AccessControl.Field(3).Value := FixtureCompany;
        AccessControl.Field(8).Value := 0;
        AccessControl.Field(9).Value := AppId;
    end;
}
