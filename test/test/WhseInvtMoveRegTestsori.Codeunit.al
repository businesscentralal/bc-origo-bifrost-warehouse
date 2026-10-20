namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InventoryMovement.Register through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97090 "Whse InvtMove Reg Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>A full register removes the open inventory movement and returns the registered document.</summary>
    [Test]
    procedure Register_FullQuantity_RegistersMovement()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        RegisteredHeader: Record "Registered Invt. Movement Hdr.";
        CreateResponse: JsonObject;
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);
        RunCreate(LineRequest(Location.Code, Item."No.", 1, FromBin.Code, ToBin.Code), CreateResponse);
        Assert.AreEqual('Success', TextValue(CreateResponse, 'status'), ResponseText(CreateResponse));
        MovementNo := CopyStr(TextValue(CreateResponse, 'movementNo'), 1, MaxStrLen(MovementNo));

        Run('{"movementNo":"' + MovementNo + '"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(MovementNo, TextValue(ResponseJson, 'movementNo'), 'The original movement number should be returned.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'registeredMovementNo'), 'A registered movement number should be returned.');
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'remainingLineCount'), 'A full register should leave no open line.');
        Assert.IsFalse(ActivityHeader.Get(ActivityHeader.Type::"Invt. Movement", MovementNo), 'The open movement should be gone.');
        Assert.IsTrue(RegisteredHeader.Get(CopyStr(TextValue(ResponseJson, 'registeredMovementNo'), 1, MaxStrLen(RegisteredHeader."No."))), 'The registered movement should exist.');
    end;

    /// <summary>A partial quantity registers and leaves the rest open.</summary>
    [Test]
    procedure Register_PartialQuantity_LeavesRemainder()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        CreateResponse: JsonObject;
        ResponseJson: JsonObject;
        MovementNo: Code[20];
        LineNo: Integer;
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);
        RunCreate(LineRequest(Location.Code, Item."No.", 4, FromBin.Code, ToBin.Code), CreateResponse);
        Assert.AreEqual('Success', TextValue(CreateResponse, 'status'), ResponseText(CreateResponse));
        MovementNo := CopyStr(TextValue(CreateResponse, 'movementNo'), 1, MaxStrLen(MovementNo));
        LineNo := IntegerValue(FirstLine(CreateResponse), 'lineNo');

        Run('{"movementNo":"' + MovementNo + '","lines":[{"lineNo":' + Format(LineNo, 0, 9) + ',"qtyToHandle":1}]}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsTrue(IntegerValue(ResponseJson, 'remainingLineCount') > 0, 'A partial register should leave an open line.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Movement", MovementNo), 'The open movement should remain.');
    end;

    /// <summary>An unknown movement number is refused.</summary>
    [Test]
    procedure Register_MissingMovement_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"movementNo":"IM-MISSING"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('movementNo', TextValue(ResponseJson, 'parameter'), 'The error should name movementNo.');
        Assert.AreEqual('Check the identifier with Warehouse.InventoryMovement.Create.', TextValue(ResponseJson, 'nextStep'), 'The next step should name the create type.');
    end;

    /// <summary>A request without a movement number is refused.</summary>
    [Test]
    procedure Register_MissingNumber_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('movementNo', TextValue(ResponseJson, 'parameter'), 'The error should name movementNo.');
    end;

    /// <summary>An unknown key is refused and leaves the movement open.</summary>
    [Test]
    procedure Register_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        CreateResponse: JsonObject;
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);
        RunCreate(LineRequest(Location.Code, Item."No.", 1, FromBin.Code, ToBin.Code), CreateResponse);
        Assert.AreEqual('Success', TextValue(CreateResponse, 'status'), ResponseText(CreateResponse));
        MovementNo := CopyStr(TextValue(CreateResponse, 'movementNo'), 1, MaxStrLen(MovementNo));

        Run('{"movementNo":"' + MovementNo + '","note":"nope"}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Movement", MovementNo), 'The open movement should stay.');
    end;

    /// <summary>
    /// A Business Central warehouse user with BIFROST WhsePost ori sees the type enabled and registers, although Business
    /// Central writes the registered inventory movement under its own permissions (#70).
    /// </summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_FullUserWithPostingGate_Registers()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        CreateResponse: JsonObject;
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);
        RunCreate(LineRequest(Location.Code, Item."No.", 1, FromBin.Code, ToBin.Code), CreateResponse);
        Assert.AreEqual('Success', TextValue(CreateResponse, 'status'), ResponseText(CreateResponse));
        MovementNo := CopyStr(TextValue(CreateResponse, 'movementNo'), 1, MaxStrLen(MovementNo));
        Commit();

        LowerToFullUserWithPostingGate(LibraryLowerPermissions);
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryMovement.Register";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Register must be enabled for a warehouse user with BIFROST WhsePost ori.');
        Assert.IsTrue(RunAsCaller('{"movementNo":"' + MovementNo + '"}', ResponseJson), 'The response should be JSON.');

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreNotEqual('', TextValue(ResponseJson, 'registeredMovementNo'), 'A registered movement number should be returned.');
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'remainingLineCount'), 'A full register should leave no open line.');
    end;

    /// <summary>Register is disabled and returns PermissionDenied without write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RegisterImpl: Codeunit "Whse InvtMove Reg Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Whse Gate Test ori would grant the activity tables, so the posting gate and not the missing write would refuse.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryMovement.Register";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Register must be disabled without write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        RegisterImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure PrepareBasicStock(var Location: Record Location; var Item: Record Item; var FromBin: Record Bin; var ToBin: Record Bin; Quantity: Decimal)
    begin
        EnsureInventoryMovementNos();
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        EnsureWarehouseEmployee(Location.Code);
        LibraryWarehouse.CreateBin(FromBin, Location.Code, 'FROM-01', '', '');
        LibraryWarehouse.CreateBin(ToBin, Location.Code, 'TO-01', '', '');
        LibraryInventory.CreateItem(Item);
        PostAdjustment(Item."No.", Location.Code, FromBin.Code, Quantity);
    end;

    local procedure EnsureInventoryMovementNos()
    var
        InventorySetup: Record "Inventory Setup";
        SeriesCode: Code[20];
    begin
        InventorySetup.Get();
        SeriesCode := LibraryUtility.GetGlobalNoSeriesCode();
        if InventorySetup."Internal Movement Nos." = '' then
            InventorySetup.Validate("Internal Movement Nos.", SeriesCode);
        if InventorySetup."Inventory Movement Nos." = '' then
            InventorySetup.Validate("Inventory Movement Nos.", SeriesCode);
        if InventorySetup."Registered Invt. Movement Nos." = '' then
            InventorySetup.Validate("Registered Invt. Movement Nos.", SeriesCode);
        InventorySetup.Modify(true);
    end;

    local procedure EnsureWarehouseEmployee(LocationCode: Code[10])
    var
        WarehouseEmployee: Record "Warehouse Employee";
        UserCode: Code[50];
    begin
        UserCode := CopyStr(UserId(), 1, MaxStrLen(UserCode));
        if UserCode = '' then
            exit;
        if WarehouseEmployee.Get(UserCode, LocationCode) then
            exit;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := false;
        WarehouseEmployee.Insert(true);
    end;

    local procedure PostAdjustment(ItemNo: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; Quantity: Decimal)
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        LibraryInventory.SelectItemJournalTemplateName(ItemJournalTemplate, ItemJournalTemplate.Type::Item);
        LibraryInventory.SelectItemJournalBatchName(ItemJournalBatch, ItemJournalTemplate.Type::Item, ItemJournalTemplate.Name);
        LibraryInventory.ClearItemJournal(ItemJournalTemplate, ItemJournalBatch);
        LibraryInventory.CreateItemJournalLine(ItemJournalLine, ItemJournalTemplate.Name, ItemJournalBatch.Name, "Item Ledger Entry Type"::"Positive Adjmt.", ItemNo, Quantity);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate("Bin Code", BinCode);
        ItemJournalLine.Modify(true);
        LibraryInventory.PostItemJournalLine(ItemJournalTemplate.Name, ItemJournalBatch.Name);
    end;

    local procedure LineRequest(LocationCode: Code[10]; ItemNo: Code[20]; Quantity: Decimal; FromBin: Code[20]; ToBin: Code[20]): Text
    begin
        exit('{"locationCode":"' + LocationCode + '","lines":[{"itemNo":"' + ItemNo + '","quantity":' + Format(Quantity, 0, 9) + ',"fromBin":"' + FromBin + '","toBin":"' + ToBin + '"}]}');
    end;

    local procedure RunCreate(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryMovement.Create", '', RequestText, ResponseJson), 'The create response should be JSON.');
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryMovement.Register", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstLine(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Lines: JsonArray;
    begin
        Assert.IsTrue(ResponseJson.Get('lines', Token), 'The response should list lines.');
        Lines := Token.AsArray();
        Lines.Get(0, Token);
        exit(Token.AsObject());
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

    local procedure RunAsCaller(RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseBody: Text;
    begin
        // The public dispatcher, called directly so the lowered caller needs no test helper codeunit.
        Clear(ResponseJson);
        RequestContent.AddText(RequestText);
        Dispatcher.Execute(
            Enum::"Message Type ori"::"Warehouse.InventoryMovement.Register",
            Enum::"Message Version ori"::"1.0",
            '',
            'Bifrost Warehouse Tests',
            'text/json',
            RequestContent,
            ResponseContent,
            ResponseContentType);
        if ResponseContent.Length() = 0 then
            exit(false);
        ResponseContent.GetSubText(ResponseBody, 1, ResponseContent.Length());
        exit(ResponseJson.ReadFrom(ResponseBody));
    end;

    local procedure LowerToFullUserWithPostingGate(var LibraryLowerPermissions: Codeunit "Library - Lower Permissions")
    begin
        // A Business Central warehouse user: direct write on the activity tables, the registered headers and lines
        // read directly and inserted only through Business Central's register codeunit. Plus the Bifrost sets and the
        // posting gate (#70).
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Full ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse RegUser Tst ori');
        LibraryLowerPermissions.AddPermissionSet('BIFROST WhsePost ori');
    end;
}
