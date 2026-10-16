namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.DefaultBin.Set, including the move off a previous default.
/// </summary>
codeunit 97082 "Whse DefBin Set Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>The first default creates fixed bin content and reports changed.</summary>
    [Test]
    procedure Set_CreatesDefaultBinContent()
    var
        Location: Record Location;
        Item: Record Item;
        BinContent: Record "Bin Content";
        ResponseJson: JsonObject;
    begin
        CreateBinAndItem(Location, Item, 'A-01', '');

        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"A-01"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The first default should succeed.');
        Assert.IsTrue(BooleanValue(ResponseJson, 'changed'), 'The first default should report changed.');
        Assert.AreEqual('', TextValue(ResponseJson, 'previousBinCode'), 'There is no previous default.');
        Assert.AreEqual(Item."Base Unit of Measure", TextValue(ResponseJson, 'unitOfMeasureCode'), 'An omitted unit uses the item base unit.');
        Assert.IsTrue(BinContent.Get(Location.Code, 'A-01', Item."No.", '', Item."Base Unit of Measure"), 'Bin content should exist.');
        Assert.IsTrue(BinContent.Default, 'The row should be the default.');
        Assert.IsTrue(BinContent.Fixed, 'The new row should be fixed.');
    end;

    /// <summary>Setting the same default again writes nothing and reports changed false.</summary>
    [Test]
    procedure Set_SameBin_IsUnchanged()
    var
        Location: Record Location;
        Item: Record Item;
        BinContent: Record "Bin Content";
        ResponseJson: JsonObject;
    begin
        CreateBinAndItem(Location, Item, 'A-01', '');
        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"A-01"}', '', ResponseJson);

        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"A-01"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The repeat should succeed.');
        Assert.IsFalse(BooleanValue(ResponseJson, 'changed'), 'The same default should not change.');
        Assert.AreEqual('A-01', TextValue(ResponseJson, 'previousBinCode'), 'The previous bin is the current bin.');
        BinContent.SetRange("Location Code", Location.Code);
        BinContent.SetRange("Item No.", Item."No.");
        Assert.AreEqual(1, BinContent.Count(), 'The repeat must not insert another row.');
        BinContent.FindFirst();
        Assert.IsTrue(BinContent.Default, 'The original row stays the default.');
    end;

    /// <summary>A new default clears the previous one before Business Central validates the second default.</summary>
    [Test]
    procedure Set_MovesPreviousDefault()
    var
        Location: Record Location;
        Item: Record Item;
        BinContent: Record "Bin Content";
        ResponseJson: JsonObject;
    begin
        CreateBinAndItem(Location, Item, 'A-01', 'A-02');
        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"A-01"}', '', ResponseJson);

        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"A-02"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The move should succeed.');
        Assert.IsTrue(BooleanValue(ResponseJson, 'changed'), 'The move should report changed.');
        Assert.AreEqual('A-01', TextValue(ResponseJson, 'previousBinCode'), 'The previous default should be named.');
        Assert.IsTrue(BinContent.Get(Location.Code, 'A-01', Item."No.", '', Item."Base Unit of Measure"), 'The old row should remain.');
        Assert.IsFalse(BinContent.Default, 'The old row should no longer be the default.');
        Assert.IsTrue(BinContent.Get(Location.Code, 'A-02', Item."No.", '', Item."Base Unit of Measure"), 'The new row should exist.');
        Assert.IsTrue(BinContent.Default, 'The new row should be the default.');
    end;

    /// <summary>A blocked bin is refused and no bin content is created.</summary>
    [Test]
    procedure Set_BlockedBin_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        BinContent: Record "Bin Content";
        ResponseJson: JsonObject;
    begin
        CreateBinAndItem(Location, Item, 'A-01', '');
        RunCreate('{"locationCode":"' + Location.Code + '","bins":[{"code":"BLOCK","blockMovement":"All"}]}', ResponseJson);

        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"BLOCK"}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), 'A blocked bin should be refused.');
        Assert.AreEqual('binCode', TextValue(ResponseJson, 'parameter'), 'The error should name binCode.');
        Assert.AreEqual('Unblock the bin or choose another.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to unblock the bin.');
        BinContent.SetRange("Location Code", Location.Code);
        BinContent.SetRange("Bin Code", 'BLOCK');
        Assert.AreEqual(0, BinContent.Count(), 'The refused call must not create bin content.');
    end;

    /// <summary>A bin-mandatory location with no bins fails before the missing-bin lookup.</summary>
    [Test]
    procedure Set_LocationWithNoBins_IsPrecondition()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        LibraryInventory.CreateItem(Item);

        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"MISSING"}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), 'No bins should be a precondition failure.');
        Assert.AreEqual('binCode', TextValue(ResponseJson, 'parameter'), 'The error should name binCode.');
        Assert.AreEqual('Choose a bin whose bin type allows it.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to choose an allowed bin.');
    end;

    /// <summary>An unknown unit of measure is InvalidParameter, not a missing bin.</summary>
    [Test]
    procedure Set_UnknownUnit_IsInvalidParameter()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        CreateBinAndItem(Location, Item, 'A-01', '');

        Run('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","binCode":"A-01","unitOfMeasureCode":"NOPE"}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), 'An unknown unit should be invalid.');
        Assert.AreEqual('unitOfMeasureCode', TextValue(ResponseJson, 'parameter'), 'The error should name the unit.');
        Assert.AreEqual('Send a unit of measure that exists for the item.', TextValue(ResponseJson, 'nextStep'), 'The next step should name a real unit.');
    end;

    /// <summary>DefaultBin.Set is disabled and returns PermissionDenied without bin content write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Set_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        SetImpl: Codeunit "Whse DefaultBin Set Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.DefaultBin.Set";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'DefaultBin.Set must be disabled without bin content write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        SetImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure CreateBinAndItem(var Location: Record Location; var Item: Record Item; FirstBin: Text; SecondBin: Text)
    var
        ResponseJson: JsonObject;
        RequestText: Text;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        LibraryInventory.CreateItem(Item);
        RequestText := '{"locationCode":"' + Location.Code + '","bins":[{"code":"' + FirstBin + '"}';
        if SecondBin <> '' then
            RequestText += ',{"code":"' + SecondBin + '"}';
        RequestText += ']}';
        RunCreate(RequestText, ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'Bin setup should succeed.');
    end;

    local procedure RunCreate(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Bin.Create", '', RequestText, ResponseJson), 'Create response should be JSON.');
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.DefaultBin.Set", Subject, RequestText, ResponseJson), 'DefaultBin response should be JSON.');
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
