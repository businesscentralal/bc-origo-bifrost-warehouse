namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Shipment.GetSourceDocuments (#52) through the public dispatcher.
/// </summary>
codeunit 97041 "Whse Ship GetSrcDocs Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>AC01: two released sales orders go onto one new shipment at the location, with lines per source document.</summary>
    [Test]
    procedure NewShipment_TwoSalesOrders_AreAdded()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Sales Header";
        SecondOrder: Record "Sales Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
    begin
        // Story #52, AC01 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(FirstOrder, Item."No.", Location.Code, 3);
        ShipmentHelper.CreateReleasedSalesOrder(SecondOrder, Item."No.", Location.Code, 4);

        Run('{"locationCode":"' + Location.Code + '","sourceDocument":"Sales Order","sourceNos":["' + FirstOrder."No." + '","' + SecondOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsTrue(BoolValue(ResponseJson, 'created'), 'A new shipment must be created.');
        Assert.AreEqual(2, IntegerValue(ResponseJson, 'linesAdded'), 'One line per sales order.');
        Assert.AreEqual(2, ArrayCount(ResponseJson, 'sourceDocuments'), 'Two source documents.');
        Assert.AreEqual(0, ArrayCount(ResponseJson, 'skipped'), 'Nothing is skipped.');
        ShipmentNo := CopyStr(TextValue(ResponseJson, 'shipmentNo'), 1, MaxStrLen(ShipmentNo));
        ShipmentLine.SetRange("No.", ShipmentNo);
        ShipmentLine.SetRange("Source No.", FirstOrder."No.");
        Assert.RecordCount(ShipmentLine, 1);
        ShipmentLine.SetRange("Source No.", SecondOrder."No.");
        Assert.RecordCount(ShipmentLine, 1);
    end;

    /// <summary>AC01: an existing open shipment gets the lines of a further sales order.</summary>
    [Test]
    procedure ExistingShipment_SecondOrder_IsAdded()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Sales Header";
        SecondOrder: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
    begin
        // Story #52, AC01 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(FirstOrder, Item."No.", Location.Code, 3);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, FirstOrder);
        ShipmentHelper.CreateReleasedSalesOrder(SecondOrder, Item."No.", Location.Code, 4);

        Run('{"sourceNos":["' + SecondOrder."No." + '"]}', ShipmentHeader."No.", ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(ShipmentHeader."No.", TextValue(ResponseJson, 'shipmentNo'), 'The existing shipment is used.');
        Assert.IsFalse(BoolValue(ResponseJson, 'created'), 'No new shipment.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'linesAdded'), 'One line is added.');
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        Assert.RecordCount(ShipmentLine, 2);
    end;

    /// <summary>AC06: a source line already on another shipment is skipped and listed with that shipment number.</summary>
    [Test]
    procedure SourceLineOnOtherShipment_IsSkipped()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Sales Header";
        SecondOrder: Record "Sales Header";
        OtherShipment: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        Skipped: JsonObject;
    begin
        // Story #52, AC06 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(FirstOrder, Item."No.", Location.Code, 3);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(OtherShipment, FirstOrder);
        ShipmentHelper.CreateReleasedSalesOrder(SecondOrder, Item."No.", Location.Code, 4);

        Run('{"locationCode":"' + Location.Code + '","sourceNos":["' + FirstOrder."No." + '","' + SecondOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'linesAdded'), 'Only the second order is added.');
        Assert.AreEqual(1, ArrayCount(ResponseJson, 'skipped'), 'The first order line is skipped.');
        Skipped := FirstEntry(ResponseJson, 'skipped');
        Assert.AreEqual(FirstOrder."No.", TextValue(Skipped, 'sourceNo'), 'The skipped source document.');
        Assert.AreEqual(OtherShipment."No.", TextValue(Skipped, 'otherShipmentNo'), 'The skipped line names the other shipment.');
    end;

    /// <summary>AC02: an unknown shipment answers RecordNotFound with the create next step and writes nothing.</summary>
    [Test]
    procedure UnknownShipment_IsNotFound()
    var
        ResponseJson: JsonObject;
    begin
        // Story #52, AC02 | Time: independent of WorkDate | Risk: none.
        Run('{"shipmentNo":"NO-SUCH-SHIP"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Create it with Warehouse.Shipment.Create or pass locationCode.', TextValue(ResponseJson, 'nextStep'), 'The next step must name Shipment.Create.');
    end;

    /// <summary>AC03: a released shipment is refused with the reopen next step and gets no lines.</summary>
    [Test]
    procedure ReleasedShipment_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Sales Header";
        SecondOrder: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        ResponseJson: JsonObject;
    begin
        // Story #52, AC03 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(FirstOrder, Item."No.", Location.Code, 1);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, FirstOrder);
        WhseShipmentRelease.Release(ShipmentHeader);
        ShipmentHelper.CreateReleasedSalesOrder(SecondOrder, Item."No.", Location.Code, 1);

        Run('{"shipmentNo":"' + ShipmentHeader."No." + '","sourceNos":["' + SecondOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Reopen it with Warehouse.Shipment.Reopen.', TextValue(ResponseJson, 'nextStep'), 'The next step must name Reopen.');
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        Assert.RecordCount(ShipmentLine, 1);
    end;

    /// <summary>AC04: no released warehouse request for the filters answers PreconditionFailed and creates no shipment.</summary>
    [Test]
    procedure NoReleasedRequest_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Story #52, AC03 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);

        Run('{"locationCode":"' + Location.Code + '"}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Release the source documents first.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the release.');
        AssertNoShipmentAt(Location.Code);
    end;

    /// <summary>AC05: a named source document at another location answers ConflictingIdentifiers and writes nothing.</summary>
    [Test]
    procedure SourceAtOtherLocation_IsRefused()
    var
        Location: Record Location;
        OtherLocation: Record Location;
        Item: Record Item;
        OtherItem: Record Item;
        ShipmentOrder: Record "Sales Header";
        OtherOrder: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
    begin
        // Story #52, AC04 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.SetupLocationAndItem(OtherLocation, OtherItem, 100);
        ShipmentHelper.CreateReleasedSalesOrder(ShipmentOrder, Item."No.", Location.Code, 1);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, ShipmentOrder);
        ShipmentHelper.CreateReleasedSalesOrder(OtherOrder, OtherItem."No.", OtherLocation.Code, 1);

        Run('{"shipmentNo":"' + ShipmentHeader."No." + '","sourceNos":["' + OtherOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use a shipment at the same location.', TextValue(ResponseJson, 'nextStep'), 'The next step must ask for the same location.');
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        Assert.RecordCount(ShipmentLine, 1);
    end;

    /// <summary>AC05: missing, wrong-typed, unknown and conflicting keys are refused with their codes and next steps.</summary>
    [Test]
    procedure CommonRefusals()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Story #52, AC05 | Time: independent of WorkDate | Risk: none.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);

        Run('{}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send shipmentNo for an existing shipment or locationCode for a new one.', TextValue(ResponseJson, 'nextStep'), 'MissingParameter next step.');

        Run('{"locationCode":12}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"locationCode":"' + Location.Code + '","sourceNos":"PO1"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceNos', TextValue(ResponseJson, 'parameter'), 'sourceNos must be an array.');

        Run('{"locationCode":"' + Location.Code + '","bin":"A"}', '', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('bin', TextValue(ResponseJson, 'parameter'), 'The unknown key must be named.');

        Run('{"shipmentNo":"A-1"}', 'B-2', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send one shipment.', TextValue(ResponseJson, 'nextStep'), 'ConflictingIdentifiers next step.');

        Run('{"locationCode":"' + Location.Code + '","sourceDocument":"Purchase Order"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use one of the values listed in the help.', TextValue(ResponseJson, 'nextStep'), 'InvalidParameter next step.');

        Run('{"locationCode":"NOLOC-X"}', '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        AssertNoShipmentAt(Location.Code);
    end;

    /// <summary>AC07: without write permission the type is disabled and answers PermissionDenied naming the permission set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        GetSourceDocsImpl: Codeunit "Whse Ship GetSrcDocs Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Story #52, AC07 | Time: independent of WorkDate | Risk: none.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.GetSourceDocuments";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'The type must be disabled without write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        GetSourceDocsImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure AssertNoShipmentAt(LocationCode: Code[10])
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        ShipmentHeader.SetRange("Location Code", LocationCode);
        Assert.RecordIsEmpty(ShipmentHeader);
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.GetSourceDocuments", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstEntry(Parent: JsonObject; Name: Text): JsonObject
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        Assert.IsTrue(Token.AsArray().Get(0, Token), Name + ' must have an entry.');
        exit(Token.AsObject());
    end;

    local procedure ArrayCount(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsArray().Count());
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
    end;

    local procedure BoolValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsValue().AsInteger());
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
}
