namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>Issue #21 strict JSON identifier validation and side-effect prevention.</summary>
codeunit 97029 "Whse Id Format Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>All nine lookup types answer malformed data with a structured error.</summary>
    [Test]
    procedure AC01_AllLookupTypes_DataNotObject_IsInvalidFormat()
    var
        MessageTypes: List of [Enum "Message Type ori"];
        MessageType: Enum "Message Type ori";
        Response: JsonObject;
    begin
        // Story #21, AC01 | Time: independent of Today/WorkDate | Risk: #18 previews use committing mode.
        MessageTypes.Add("Message Type ori"::"Warehouse.Shipment.Post");
        MessageTypes.Add("Message Type ori"::"Warehouse.Shipment.PreviewPost");
        MessageTypes.Add("Message Type ori"::"Warehouse.Receipt.Post");
        MessageTypes.Add("Message Type ori"::"Warehouse.Receipt.Post.Preview");
        MessageTypes.Add("Message Type ori"::"Warehouse.Pick.Create");
        MessageTypes.Add("Message Type ori"::"Warehouse.Pick.Register");
        MessageTypes.Add("Message Type ori"::"Warehouse.Putaway.Create");
        MessageTypes.Add("Message Type ori"::"Warehouse.Putaway.Register");
        MessageTypes.Add("Message Type ori"::"Warehouse.Activity.Get");
        foreach MessageType in MessageTypes do begin
            SendRequest(MessageType, '', '[]', Response);
            AssertFormatResponse(Response, 'InvalidParameterFormat', 'data', 'a JSON object');
            SendRequest(MessageType, '', 'not json', Response);
            AssertFormatResponse(Response, 'InvalidParameterFormat', 'data', 'a JSON object');
        end;
    end;

    /// <summary>Every shipment identifier rejects every non-string JSON value.</summary>
    [Test]
    procedure AC02_ShipmentKeys_WrongJsonTypes_AreInvalidFormat()
    var
        Keys: List of [Text];
        Values: List of [Text];
        KeyName: Text;
        Value: Text;
        Response: JsonObject;
    begin
        // Story #21, AC02 | Time: independent of Today/WorkDate | Risk: no fixture lookup allowed.
        Keys.AddRange('shipmentNo', 'no', 'systemId', 'recordSystemId', 'id');
        Values.AddRange('null', '12', 'true', '{}', '[]');
        foreach KeyName in Keys do
            foreach Value in Values do begin
                SendRequest("Message Type ori"::"Warehouse.Shipment.Post", '', '{"' + KeyName + '":' + Value + '}', Response);
                AssertFormatResponse(Response, 'InvalidParameterFormat', KeyName, 'a JSON string');
            end;
    end;

    /// <summary>A valid subject never permits posting when an identifier has the wrong type.</summary>
    [Test]
    procedure AC03_ValidSubject_WrongKey_DoesNotPost()
    var
        Item: Record Item;
        Location: Record Location;
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        PostedHeader: Record "Posted Whse. Shipment Header";
        Response: JsonObject;
        PostedBefore: Integer;
    begin
        // Story #21, AC03 | Time: library posting dates | Risk: own generated document only.
        // [GIVEN] A newly created, postable shipment.
        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        PostedHeader.SetRange("Whse. Shipment No.", ShipmentHeader."No.");
        PostedBefore := PostedHeader.Count();
        // [WHEN] A valid subject accompanies a wrong-typed identifier.
        SendRequest("Message Type ori"::"Warehouse.Shipment.Post", ShipmentHeader."No.", '{"no":12}', Response);
        // [THEN] Validation precedes posting and the source remains.
        AssertFormatResponse(Response, 'InvalidParameterFormat', 'no', 'a JSON string');
        Assert.AreEqual(PostedBefore, PostedHeader.Count(), 'No shipment must be posted.');
        Assert.IsTrue(ShipmentHeader.Get(ShipmentHeader."No."), 'The original shipment must remain.');
    end;

    /// <summary>Several invalid identifiers are aggregated in key-spec order.</summary>
    [Test]
    procedure AC04_TwoWrongKeys_ReturnOrderedMultipleErrors()
    var
        Response: JsonObject;
    begin
        // Story #21, AC04 | Time: independent of Today/WorkDate | Risk: none.
        SendRequest("Message Type ori"::"Warehouse.Shipment.Post", '', '{"shipmentNo":null,"systemId":7}', Response);
        AssertMultipleErrors(Response, 'systemId', 'shipmentNo');
        SendRequest("Message Type ori"::"Warehouse.Pick.Register", '', '{"pickNo":null,"systemId":7}', Response);
        AssertMultipleErrors(Response, 'systemId', 'pickNo');
        SendRequest("Message Type ori"::"Warehouse.Activity.Get", '', '{"no":null,"systemId":7}', Response);
        AssertMultipleErrors(Response, 'systemId', 'no');
    end;

    /// <summary>Existing empty and invalid GUID semantics remain intact.</summary>
    [Test]
    procedure AC05_EmptyAndInvalidGuid_PreserveErrors()
    var
        Response: JsonObject;
    begin
        // Story #21, AC05 | Time: independent of Today/WorkDate | Risk: optional Activity.Get remains a collection.
        SendRequest("Message Type ori"::"Warehouse.Shipment.Post", '', '{"shipmentNo":""}', Response);
        AssertProperty(Response, 'code', 'MissingParameter');
        SendRequest("Message Type ori"::"Warehouse.Shipment.Post", '', '{}', Response);
        AssertProperty(Response, 'code', 'MissingParameter');
        SendRequest("Message Type ori"::"Warehouse.Shipment.Post", '', '{"systemId":"not-a-guid"}', Response);
        AssertProperty(Response, 'code', 'InvalidParameterFormat');
        AssertProperty(Response, 'parameter', 'systemId');
    end;

    /// <summary>All Activity.Get aliases reject non-string values before record lookup.</summary>
    [Test]
    procedure ActivityAliases_WrongJsonTypes_AreInvalidFormat()
    var
        Keys: List of [Text];
        Values: List of [Text];
        KeyName: Text;
        Value: Text;
        Response: JsonObject;
    begin
        // Issues #21/#37: keep strict validation for the newly supported aliases.
        Keys.AddRange('no', 'activityNo', 'systemId', 'recordSystemId', 'id');
        Values.AddRange('null', '12', 'true', '{}', '[]');
        foreach KeyName in Keys do
            foreach Value in Values do begin
                SendRequest("Message Type ori"::"Warehouse.Activity.Get", '', '{"' + KeyName + '":' + Value + '}', Response);
                AssertFormatResponse(Response, 'InvalidParameterFormat', KeyName, 'a JSON string');
            end;
    end;

    local procedure SendRequest(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var Response: JsonObject)
    begin
        Assert.IsTrue(Helper.RunMessage(MessageType, Subject, RequestText, Response, false), 'Response must be JSON.');
    end;

    local procedure AssertFormatResponse(Response: JsonObject; ExpectedCode: Text; Parameter: Text; Expected: Text)
    begin
        AssertProperty(Response, 'status', 'Error');
        AssertProperty(Response, 'code', ExpectedCode);
        AssertProperty(Response, 'parameter', Parameter);
        AssertProperty(Response, 'expected', Expected);
    end;

    local procedure AssertProperty(Response: JsonObject; Name: Text; Expected: Text)
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Response.Get(Name, Token), Name + ' must be present.');
        Assert.AreEqual(Expected, Token.AsValue().AsText(), Name + ' must match.');
    end;

    local procedure AssertMultipleErrors(Response: JsonObject; FirstKey: Text; SecondKey: Text)
    var
        Token: JsonToken;
        Errors: JsonArray;
    begin
        AssertProperty(Response, 'code', 'MultipleErrors');
        Assert.IsTrue(Response.Get('errors', Token), 'Errors must be present.');
        Errors := Token.AsArray();
        Assert.AreEqual(2, Errors.Count(), 'Exactly two format errors expected.');
        Errors.Get(0, Token);
        AssertProperty(Token.AsObject(), 'code', 'InvalidParameterFormat');
        AssertProperty(Token.AsObject(), 'parameter', FirstKey);
        AssertProperty(Token.AsObject(), 'expected', 'a JSON string');
        Errors.Get(1, Token);
        AssertProperty(Token.AsObject(), 'code', 'InvalidParameterFormat');
        AssertProperty(Token.AsObject(), 'parameter', SecondKey);
        AssertProperty(Token.AsObject(), 'expected', 'a JSON string');
    end;
}
