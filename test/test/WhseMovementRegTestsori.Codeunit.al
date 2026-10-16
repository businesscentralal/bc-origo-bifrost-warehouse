namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Movement.Register through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97084 "Whse Movement Reg Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>Registering a created movement returns the registered movement and leaves nothing open.</summary>
    [Test]
    procedure Register_CreatedMovement_RegistersAll()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        Zone: Record Zone;
        ActivityHeader: Record "Warehouse Activity Header";
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        CreateResponse: JsonObject;
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        EnsureDefaultDirectedEmployee(Location.Code);
        EnsureMovementWorksheetTemplate();
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.UpdateInventoryOnLocationWithDirectedPutAwayAndPick(Item."No.", Location.Code, 5, false);
        LibraryWarehouse.FindZone(Zone, Location.Code, LibraryWarehouse.SelectBinType(false, false, true, true), false);
        LibraryWarehouse.FindBin(FromBin, Location.Code, Zone.Code, 1);
        LibraryWarehouse.FindBin(ToBin, Location.Code, Zone.Code, 2);
        RunCreate('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}', CreateResponse);
        Assert.AreEqual('Success', TextValue(CreateResponse, 'status'), ResponseText(CreateResponse));
        MovementNo := CopyStr(TextValue(CreateResponse, 'movementNo'), 1, MaxStrLen(MovementNo));

        Run('{"movementNo":"' + MovementNo + '"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(MovementNo, TextValue(ResponseJson, 'movementNo'), 'The original movement number should be returned.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'registeredMovementNo'), 'A registered movement number should be returned.');
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'remainingLineCount'), 'A full register should leave no open line.');
        Assert.IsFalse(ActivityHeader.Get(ActivityHeader.Type::Movement, MovementNo), 'The open movement should be gone.');
        Assert.IsTrue(RegisteredHeader.Get(RegisteredHeader.Type::Movement, CopyStr(TextValue(ResponseJson, 'registeredMovementNo'), 1, MaxStrLen(RegisteredHeader."No."))), 'The registered movement should exist.');
    end;

    /// <summary>A movement number that does not exist uses the activity lookup next step.</summary>
    [Test]
    procedure Register_UnknownNumber_IsNotFound()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"movementNo":"WM-MISSING"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('movementNo', TextValue(ResponseJson, 'parameter'), 'The error should name movementNo.');
        Assert.AreEqual('Check the identifier with Warehouse.Activity.Get (activityType Movement).', TextValue(ResponseJson, 'nextStep'), 'The next step should name Activity.Get.');
    end;

    /// <summary>movementNo and systemId are both required to be absent before MissingParameter.</summary>
    [Test]
    procedure Register_MissingIdentifier_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('movementNo', TextValue(ResponseJson, 'parameter'), 'The error should name movementNo.');
    end;

    /// <summary>An unknown key is refused and the movement stays open.</summary>
    [Test]
    procedure Register_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        Zone: Record Zone;
        ActivityHeader: Record "Warehouse Activity Header";
        CreateResponse: JsonObject;
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        EnsureDefaultDirectedEmployee(Location.Code);
        EnsureMovementWorksheetTemplate();
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.UpdateInventoryOnLocationWithDirectedPutAwayAndPick(Item."No.", Location.Code, 5, false);
        LibraryWarehouse.FindZone(Zone, Location.Code, LibraryWarehouse.SelectBinType(false, false, true, true), false);
        LibraryWarehouse.FindBin(FromBin, Location.Code, Zone.Code, 1);
        LibraryWarehouse.FindBin(ToBin, Location.Code, Zone.Code, 2);
        RunCreate('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}', CreateResponse);
        Assert.AreEqual('Success', TextValue(CreateResponse, 'status'), ResponseText(CreateResponse));
        MovementNo := CopyStr(TextValue(CreateResponse, 'movementNo'), 1, MaxStrLen(MovementNo));

        Run('{"movementNo":"' + MovementNo + '","note":"nope"}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::Movement, MovementNo), 'The open movement should stay.');
    end;

    /// <summary>Register is disabled and returns PermissionDenied without activity write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        RegisterImpl: Codeunit "Whse Movement Reg Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Movement.Register";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Register must be disabled without activity write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        RegisterImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure RunCreate(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Movement.Create", '', RequestText, ResponseJson), 'The create response should be JSON.');
    end;

    local procedure EnsureDefaultDirectedEmployee(LocationCode: Code[10])
    var
        WarehouseEmployee: Record "Warehouse Employee";
        Existing: Record "Warehouse Employee";
        UserCode: Code[50];
    begin
        UserCode := CopyStr(UserId(), 1, MaxStrLen(UserCode));
        if UserCode = '' then
            exit;
        Existing.SetRange("User ID", UserCode);
        Existing.SetRange(Default, true);
        Existing.SetFilter("Location Code", '<>%1', LocationCode);
        while Existing.FindFirst() do begin
            Existing.Default := false;
            Existing.Modify(true);
        end;
        if WarehouseEmployee.Get(UserCode, LocationCode) then begin
            if not WarehouseEmployee.Default then begin
                WarehouseEmployee.Default := true;
                WarehouseEmployee.Modify(true);
            end;
            exit;
        end;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := true;
        WarehouseEmployee.Insert(true);
    end;

    local procedure EnsureMovementWorksheetTemplate()
    var
        WorksheetTemplate: Record "Whse. Worksheet Template";
    begin
        WorksheetTemplate.SetRange(Type, WorksheetTemplate.Type::Movement);
        if not WorksheetTemplate.IsEmpty() then
            exit;
        WorksheetTemplate.Init();
        WorksheetTemplate.Name := 'MOVEMENT';
        WorksheetTemplate.Validate(Type, WorksheetTemplate.Type::Movement);
        WorksheetTemplate.Description := 'Movement';
        WorksheetTemplate.Insert(true);
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Movement.Register", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
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
