namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Bin.Get through the public dispatcher, including help text in both languages.
/// </summary>
codeunit 97080 "Whse Bin Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>Get returns the bin created by Warehouse.Bin.Create.</summary>
    [Test]
    procedure Get_ReturnsCreatedBin()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
        Result: JsonArray;
        Token: JsonToken;
        BinJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        RunCreate('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01","description":"Aisle A","ranking":4}]}', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'Create should succeed before Get.');

        RunGet('{"locationCode":"' + Location.Code + '","binCode":"A-01","includeContent":true}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'Get should succeed.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'The bin filter should match one row.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'result should be present.');
        Result := Token.AsArray();
        Assert.AreEqual(1, Result.Count(), 'One bin should be returned.');
        Result.Get(0, Token);
        BinJson := Token.AsObject();
        Assert.AreEqual(Location.Code, TextValue(BinJson, 'locationCode'), 'locationCode should match.');
        Assert.AreEqual('A-01', TextValue(BinJson, 'code'), 'code should match.');
        Assert.AreEqual('Aisle A', TextValue(BinJson, 'description'), 'description should match.');
        Assert.AreEqual(4, IntegerValue(BinJson, 'ranking'), 'ranking should match.');
        Assert.AreEqual('', TextValue(BinJson, 'blockMovement'), 'An open bin has a blank block.');
        Assert.IsTrue(BooleanValue(BinJson, 'empty'), 'A new bin is empty.');
        Assert.IsTrue(BinJson.Get('content', Token), 'includeContent should add content.');
        Assert.AreEqual(0, Token.AsArray().Count(), 'A new bin has no content.');
    end;

    /// <summary>Paging returns one row and keeps the unpaged count.</summary>
    [Test]
    procedure Get_PagesRowsAndReportsUnpagedCount()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        RunCreate('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01"},{"code":"A-02"}]}', ResponseJson);

        RunGet('{"locationCode":"' + Location.Code + '","skip":1,"take":1}', '', ResponseJson);

        Assert.AreEqual(2, IntegerValue(ResponseJson, 'noOfRecords'), 'The count should include both bins.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'skip'), 'skip should be echoed.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'take'), 'take should be echoed.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'result should be present.');
        Assert.AreEqual(1, Token.AsArray().Count(), 'The page should contain one bin.');
        Token.AsArray().Get(0, Token);
        Assert.AreEqual('A-02', TextValue(Token.AsObject(), 'code'), 'Skip should move to the second bin.');
    end;

    /// <summary>empty = false matches nothing when every new bin is empty.</summary>
    [Test]
    procedure Get_EmptyFalse_ReturnsNoRows()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        RunCreate('{"locationCode":"' + Location.Code + '","bins":[{"code":"A-01"}]}', ResponseJson);

        RunGet('{"locationCode":"' + Location.Code + '","empty":false}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'A zero-match filter should succeed.');
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'noOfRecords'), 'No bin is non-empty.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'result should be present.');
        Assert.AreEqual(0, Token.AsArray().Count(), 'The result should be empty.');
    end;

    /// <summary>An unknown location is RecordNotFound.</summary>
    [Test]
    procedure Get_UnknownLocation_IsRecordNotFound()
    var
        ResponseJson: JsonObject;
    begin
        RunGet('{"locationCode":"NOSUCH"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), 'An unknown location should be RecordNotFound.');
        Assert.AreEqual('locationCode', TextValue(ResponseJson, 'parameter'), 'The error should name locationCode.');
        Assert.AreEqual('Check the location code and try again.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to check the location.');
    end;

    /// <summary>subject and locationCode cannot name different locations.</summary>
    [Test]
    procedure Get_ConflictingLocation_IsRefused()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        RunGet('{"locationCode":"' + Location.Code + '"}', 'OTHER', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), 'Different locations should conflict.');
        Assert.AreEqual('Send one location: subject or locationCode.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to send one location.');
    end;

    /// <summary>Help translates the conflict in Icelandic and keeps the English source.</summary>
    [Test]
    procedure Get_HelpTranslatesConflict()
    var
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        AssertConflictHelp(1033);
        AssertConflictHelp(1039);
        GlobalLanguage(OriginalLanguage);
    end;

    /// <summary>Get is disabled and returns PermissionDenied without bin read permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Get_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        GetImpl: Codeunit "Whse Bin Get Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Bin.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Get must be disabled without bin read permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        GetImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Read ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the read permission set.');
    end;

    local procedure AssertConflictHelp(LanguageId: Integer)
    var
        Contract: Interface "Msg Contract ori";
        Errors: JsonArray;
        Entry: JsonToken;
        ErrorJson: JsonObject;
        FoundConflict: Boolean;
    begin
        GlobalLanguage(LanguageId);
        Contract := Enum::"Message Type ori"::"Warehouse.Bin.Get";
        Assert.IsTrue(Contract.GetErrors(Errors), 'Help must declare errors.');
        foreach Entry in Errors do begin
            ErrorJson := Entry.AsObject();
            if TextValue(ErrorJson, 'code') = 'ConflictingIdentifiers' then begin
                FoundConflict := true;
                if LanguageId = 1039 then
                    Assert.AreEqual('Sendu eina staðsetningu: subject eða locationCode.', TextValue(ErrorJson, 'nextStep'), 'Icelandic help must translate the next step.')
                else
                    Assert.AreEqual('Send one location: subject or locationCode.', TextValue(ErrorJson, 'nextStep'), 'English help must keep the next step.');
            end;
        end;
        Assert.IsTrue(FoundConflict, 'Help must declare ConflictingIdentifiers.');
    end;

    local procedure RunCreate(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Bin.Create", '', RequestText, ResponseJson), 'Create response should be JSON.');
    end;

    local procedure RunGet(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Bin.Get", Subject, RequestText, ResponseJson), 'Get response should be JSON.');
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

    local procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;
}
