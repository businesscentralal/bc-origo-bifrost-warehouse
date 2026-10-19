namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Bin.Create through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97081 "Whse Bin Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>A bin-mandatory location accepts several bins in one call.</summary>
    [Test]
    procedure Create_TwoBins_InsertsBoth()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
        Bins: JsonArray;
        Token: JsonToken;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","description":"Aisle A"},{"code":"A-02","description":"Aisle A end","ranking":10,"dedicated":true,"blockMovement":"Outbound"}]}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'Create should succeed.');
        Assert.AreEqual(2, IntegerValue(ResponseJson, 'count'), 'Both bins should be counted.');
        Assert.IsTrue(ResponseJson.Get('bins', Token), 'The response should list the bins.');
        Bins := Token.AsArray();
        Assert.AreEqual(2, Bins.Count(), 'Both bins should be returned.');
        Assert.IsTrue(Bin.Get(Location.Code, 'A-01'), 'A-01 should exist.');
        Assert.AreEqual('Aisle A', Bin.Description, 'A-01 description should be stored.');
        Assert.IsTrue(Bin.Empty, 'A new bin stays empty.');
        Assert.AreEqual(Bin."Block Movement"::" ", Bin."Block Movement", 'An omitted block stays open.');
        Assert.IsTrue(Bin.Get(Location.Code, 'A-02'), 'A-02 should exist.');
        Assert.AreEqual(10, Bin."Bin Ranking", 'Ranking should be stored.');
        Assert.IsTrue(Bin.Dedicated, 'Dedicated should be stored.');
        Assert.AreEqual(Bin."Block Movement"::Outbound, Bin."Block Movement", 'Outbound should be stored.');
    end;

    /// <summary>A repeated code in one request writes none of the bins.</summary>
    [Test]
    procedure Create_DuplicateInRequest_WritesNothing()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01"},{"code":"A-01"}]}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), 'The repeated code should be invalid.');
        Assert.AreEqual('bins[1].code', TextValue(ResponseJson, 'parameter'), 'The error should name the repeated bin.');
        Assert.AreEqual('Read Warehouse.Bin.Get or choose another code.', TextValue(ResponseJson, 'nextStep'), 'The next step should point at Bin.Get.');
        Bin.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, Bin.Count(), 'A failed request must not insert any bin.');
    end;

    /// <summary>A bin that already exists is refused and the existing row stays.</summary>
    [Test]
    procedure Create_ExistingBin_LeavesTheOriginal()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","description":"Original"}]}', '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The first create should succeed.');

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","description":"Replacement"},{"code":"A-02"}]}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), 'The existing code should be invalid.');
        Assert.IsTrue(Bin.Get(Location.Code, 'A-01'), 'The original bin should remain.');
        Assert.AreEqual('Original', Bin.Description, 'The failed call must not change the original bin.');
        Assert.IsFalse(Bin.Get(Location.Code, 'A-02'), 'The sibling bin must not be written.');
    end;

    /// <summary>A location that is not bin-mandatory is refused before any insert.</summary>
    [Test]
    procedure Create_LocationWithoutBinMandatory_IsRefused()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01"}]}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), 'Bin Mandatory must be on.');
        Assert.AreEqual('locationCode', TextValue(ResponseJson, 'parameter'), 'The error should name locationCode.');
        Assert.AreEqual('Turn on Bin Mandatory on the location first.', TextValue(ResponseJson, 'nextStep'), 'The next step should name Bin Mandatory.');
        Bin.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, Bin.Count(), 'Nothing should be written.');
    end;

    /// <summary>empty = false is refused because Bin.Empty is not writable.</summary>
    [Test]
    procedure Create_EmptyFalse_IsRefused()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","empty":false}]}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), 'empty false should be refused.');
        Assert.AreEqual('bins[0].empty', TextValue(ResponseJson, 'parameter'), 'The error should name empty.');
        Bin.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, Bin.Count(), 'The refused bin must not be inserted.');
    end;

    /// <summary>zoneCode on a basic location is refused and writes nothing.</summary>
    [Test]
    procedure Create_ZoneOnBasicLocation_IsRefused()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","zoneCode":"PICK"}]}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), 'A zone on a basic location should be refused.');
        Assert.AreEqual('Leave them blank for basic warehouse locations.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to leave zone and bin type blank.');
        Bin.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, Bin.Count(), 'The refused bin must not be inserted.');
    end;

    /// <summary>Two independent bin failures stay all-or-nothing.</summary>
    [Test]
    procedure Create_SeveralBinFailures_WritesNothing()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","zoneCode":"PICK","empty":false}]}', '', ResponseJson);

        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), 'Several bin failures should be collected.');
        Bin.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, Bin.Count(), 'Collected failures must not insert a bin.');
    end;

    /// <summary>An unknown key is refused and no bin is written.</summary>
    [Test]
    procedure Create_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Bin: Record Bin;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","note":"nope","bins":[{"code":"A-01"}]}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), 'An unknown key should be refused.');
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Bin.SetRange("Location Code", Location.Code);
        Assert.IsTrue(Bin.IsEmpty(), 'A refused call must not write a bin.');
    end;

    /// <summary>A request without bins is MissingParameter.</summary>
    [Test]
    procedure Create_MissingBins_IsMissingParameter()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '"}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), 'Missing bins should be MissingParameter.');
        Assert.AreEqual('bins', TextValue(ResponseJson, 'parameter'), 'The error should name bins.');
    end;

    /// <summary>Create is disabled and returns PermissionDenied without bin write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        CreateImpl: Codeunit "Whse Bin Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Bin.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without bin write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Bin.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsInteger());
    end;
}
