namespace Origo.Bifrost.Warehouse.Test;

using System.TestLibraries.Utilities;

/// <summary>
/// Smoke test proving the Warehouse test app can be built and run.
/// </summary>
codeunit 97000 "Warehouse Smoke Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure SmokeTest()
    var
        Assert: Codeunit "Library Assert";
    begin
        Assert.IsTrue(true, 'Warehouse test app is running.');
    end;
}