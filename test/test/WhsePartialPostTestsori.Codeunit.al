namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests per-line quantities on Warehouse.Receipt.Post, Warehouse.Shipment.Post and their previews (#54), and the
/// generic write blocks on shipment status and the receipt and shipment quantities (#53 AC09, #54 AC09).
/// </summary>
codeunit 97046 "Whse Partial Post Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>AC01: a partial qtyToReceive posts that quantity and answers posted and remaining per line.</summary>
    [Test]
    procedure ReceiptPost_PartialLine_PostsPartOfIt()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        PostedReceiptLine: Record "Posted Whse. Receipt Line";
        ResponseJson: JsonObject;
        Line: JsonObject;
    begin
        // Story #54, AC01 | Time: helper posts at WorkDate | Risk: none.
        CreateReceipt(ReceiptLine, 5);

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":3}]}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Line := FirstEntry(ResponseJson, 'lines');
        Assert.AreEqual(3, DecimalValue(Line, 'quantityPosted'), 'Three are received.');
        Assert.AreEqual(2, DecimalValue(Line, 'quantityRemaining'), 'Two remain on the receipt.');
        ReceiptLine.Get(ReceiptLine."No.", ReceiptLine."Line No.");
        Assert.AreEqual(2, ReceiptLine."Qty. Outstanding", 'Two stay outstanding on the receipt line.');
        PostedReceiptLine.SetRange("Whse. Receipt No.", ReceiptLine."No.");
        PostedReceiptLine.CalcSums(Quantity);
        Assert.AreEqual(3, PostedReceiptLine.Quantity, 'The posted receipt holds three.');
    end;

    /// <summary>AC03: a quantity above the outstanding quantity, or negative, is refused and nothing changes.</summary>
    [Test]
    procedure ReceiptPost_QuantityOutOfRange_IsRefused()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC03 | Time: independent of WorkDate | Risk: none.
        CreateReceipt(ReceiptLine, 5);

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":6}]}', ResponseJson);
        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Read the outstanding quantity on the line and lower it.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the outstanding quantity.');

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":-1}]}', ResponseJson);
        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    /// <summary>AC04: a lineNo that is not on the receipt is refused with the read-the-lines next step.</summary>
    [Test]
    procedure ReceiptPost_UnknownLine_IsRefused()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC04 | Time: independent of WorkDate | Risk: none.
        CreateReceipt(ReceiptLine, 5);

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":999999,"qtyToReceive":1}]}', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Read the lines first.', TextValue(ResponseJson, 'nextStep'), 'The next step must ask to read the lines.');
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    /// <summary>AC07: zero on every line is refused with PreconditionFailed and nothing changes.</summary>
    [Test]
    procedure ReceiptPost_AllZero_IsRefused()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC07 | Time: independent of WorkDate | Risk: none.
        CreateReceipt(ReceiptLine, 5);

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":0}]}', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    /// <summary>AC06: missing, wrong-typed and unknown line keys are refused.</summary>
    [Test]
    procedure ReceiptPost_LineFormatRefusals()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC06 | Time: independent of WorkDate | Risk: none.
        CreateReceipt(ReceiptLine, 5);

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"qtyToReceive":1}]}', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('lines[0].lineNo', TextValue(ResponseJson, 'parameter'), 'The missing key is named.');

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":"3"}]}', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToShip":3}]}', ResponseJson);
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.IsTrue(ResponseText(ResponseJson).Contains('UnknownParameter'), 'qtyToShip is not a receipt key.');

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", '{"receiptNo":"' + ReceiptLine."No." + '","post":true}', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    /// <summary>AC02: a partial qtyToShip posts that quantity and answers posted and remaining per line.</summary>
    [Test]
    procedure ShipmentPost_PartialLine_PostsPartOfIt()
    var
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
        Line: JsonObject;
    begin
        // Story #54, AC02 | Time: helper posts at WorkDate | Risk: none.
        CreateShipment(ShipmentLine, 5, false);

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Post", '{"shipmentNo":"' + ShipmentLine."No." + '","lines":[{"lineNo":' + Format(ShipmentLine."Line No.") + ',"qtyToShip":2}]}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Line := FirstEntry(ResponseJson, 'lines');
        Assert.AreEqual(2, DecimalValue(Line, 'quantityPosted'), 'Two are shipped.');
        Assert.AreEqual(3, DecimalValue(Line, 'quantityRemaining'), 'Three remain on the shipment.');
        ShipmentLine.Get(ShipmentLine."No.", ShipmentLine."Line No.");
        Assert.AreEqual(3, ShipmentLine."Qty. Outstanding", 'Three stay outstanding.');
    end;

    /// <summary>AC05: qtyToShip above the picked quantity at a pick location is refused with the register-the-pick next step.</summary>
    [Test]
    procedure ShipmentPost_AbovePicked_IsRefused()
    var
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC05 | Time: independent of WorkDate | Risk: none.
        CreateShipment(ShipmentLine, 5, true);

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Post", '{"shipmentNo":"' + ShipmentLine."No." + '","lines":[{"lineNo":' + Format(ShipmentLine."Line No.") + ',"qtyToShip":1}]}', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Register the pick first.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the pick.');
        ShipmentLine.Get(ShipmentLine."No.", ShipmentLine."Line No.");
        Assert.AreEqual(5, ShipmentLine."Qty. Outstanding", 'Nothing is shipped.');
    end;

    /// <summary>AC02: the receipt preview takes the same lines and rolls the quantity back.</summary>
    [Test]
    procedure ReceiptPreview_WithLines_RollsBack()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC02 | Time: helper posts at WorkDate | Risk: preview needs Omit Commit false.
        CreateReceipt(ReceiptLine, 5);

        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.PreviewPost", '', '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":2}]}', ResponseJson, false), 'The response should be JSON.');

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        AssertReceiptUnchanged(ReceiptLine, 5);

        // Zero on the only line inside the preview leaves nothing to post: the lines are applied in the preview run.
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.PreviewPost", '', '{"receiptNo":"' + ReceiptLine."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":0}]}', ResponseJson, false), 'The response should be JSON.');
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    /// <summary>AC02: the shipment preview refuses an out-of-range line like the post does.</summary>
    [Test]
    procedure ShipmentPreview_QuantityOutOfRange_IsRefused()
    var
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
    begin
        // Story #54, AC02 + AC03 | Time: independent of WorkDate | Risk: preview needs Omit Commit false.
        CreateShipment(ShipmentLine, 5, false);

        Assert.IsTrue(ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", '', '{"shipmentNo":"' + ShipmentLine."No." + '","lines":[{"lineNo":' + Format(ShipmentLine."Line No.") + ',"qtyToShip":9}]}', ResponseJson, false), 'The response should be JSON.');

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    /// <summary>#53 AC09 and #54 AC09: generic writes of shipment status and the receipt and shipment quantities are refused and point at the dedicated types.</summary>
    [Test]
    procedure GenericWrite_StatusAndQuantities_AreRefusedAndHinted()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        ReceiptLine: Record "Warehouse Receipt Line";
        TempArgument: Record "Message Argument ori" temporary;
    begin
        // Story #53 AC09, #54 AC09 | Time: independent of WorkDate | Risk: none.
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Shipment Header", true), 'The shipment header stays closed, including force.');
        Assert.AreEqual('Warehouse.Shipment.Release, Warehouse.Shipment.Reopen', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Shipment Header", ShipmentHeader.FieldNo(Status)), 'Status hint.');
        Assert.AreEqual('Warehouse.Receipt.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Receipt Line", ReceiptLine.FieldNo("Qty. to Receive")), 'Qty. to Receive hint.');
        Assert.AreEqual('Warehouse.Shipment.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Shipment Line", ShipmentLine.FieldNo("Qty. to Ship")), 'Qty. to Ship hint.');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Shipment Header"), 'Reads stay allowed.');
        AssertGenericSetRefused('Warehouse Shipment Header', '{"tableName":"Warehouse Shipment Header","force":true,"data":[{"primaryKey":{"No.":"SH-X"},"fields":{"Status":"Released"}}]}', 'Warehouse.Shipment.Release');
        AssertGenericSetRefused('Warehouse Receipt Line', '{"tableName":"Warehouse Receipt Line","force":true,"data":[{"primaryKey":{"No.":"RE-X","Line No.":10000},"fields":{"Qty. to Receive":1}}]}', 'Warehouse.Receipt.Post');
        AssertGenericSetRefused('Warehouse Shipment Line', '{"tableName":"Warehouse Shipment Line","force":true,"data":[{"primaryKey":{"No.":"SH-X","Line No.":10000},"fields":{"Qty. to Ship":1}}]}', 'Warehouse.Shipment.Post');
    end;

    /// <summary>#67 item 3: an unknown top-level key no longer hides the problems in the lines (1033 and 1039).</summary>
    [Test]
    procedure ReceiptPost_UnknownKeyAndLineProblems_AreCollected()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
        RequestText: Text;
        OriginalLanguage: Integer;
    begin
        // Issue #67, AC1 (item 3) | Time: independent of WorkDate | Risk: none.
        CreateReceipt(ReceiptLine, 5);
        RequestText := '{"receiptNo":"' + ReceiptLine."No." + '","post":true,"lines":[{"lineNo":999999,"qtyToReceive":1},{"lineNo":' + Format(ReceiptLine."Line No.") + ',"qtyToReceive":"3"}]}';

        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", RequestText, ResponseJson);
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Nothing was posted.', TextValue(ResponseJson, 'error'), 'English summary.');
        Assert.AreEqual('post:UnknownParameter,lines[0].lineNo:InvalidLine,lines[1].qtyToReceive:InvalidParameterFormat', ErrorList(ResponseJson), 'Every problem is listed.');

        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1039);
        Run(Enum::"Message Type ori"::"Warehouse.Receipt.Post", RequestText, ResponseJson);
        GlobalLanguage(OriginalLanguage);
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Ekkert var bókað.', TextValue(ResponseJson, 'error'), 'Icelandic summary.');
        Assert.AreEqual('post:UnknownParameter,lines[0].lineNo:InvalidLine,lines[1].qtyToReceive:InvalidParameterFormat', ErrorList(ResponseJson), 'Every problem is listed in Icelandic too.');
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    /// <summary>#67 item 5: the receipt preview summary answers in the caller language.</summary>
    [Test]
    procedure ReceiptPreview_Summary_IsTranslated()
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
        OriginalLanguage: Integer;
    begin
        // Issue #67, AC2 (item 5) | Time: helper posts at WorkDate | Risk: preview needs Omit Commit false.
        CreateReceipt(ReceiptLine, 5);
        OriginalLanguage := GlobalLanguage();

        GlobalLanguage(1039);
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.PreviewPost", '', '{"receiptNo":"' + ReceiptLine."No." + '"}', ResponseJson, false), 'The response should be JSON.');
        GlobalLanguage(OriginalLanguage);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsTrue(TextValue(ResponseJson, 'summary').StartsWith('Forsýning bókunar vöruhúsamóttöku ' + ReceiptLine."No."), 'Icelandic summary: ' + TextValue(ResponseJson, 'summary'));

        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.PreviewPost", '', '{"receiptNo":"' + ReceiptLine."No." + '"}', ResponseJson, false), 'The response should be JSON.');
        Assert.IsTrue(TextValue(ResponseJson, 'summary').StartsWith('Warehouse Receipt ' + ReceiptLine."No."), 'English summary: ' + TextValue(ResponseJson, 'summary'));
        AssertReceiptUnchanged(ReceiptLine, 5);
    end;

    local procedure ErrorList(ResponseJson: JsonObject): Text
    var
        Token: JsonToken;
        Entry: JsonToken;
        Entries: TextBuilder;
    begin
        if not ResponseJson.Get('errors', Token) then
            exit('');
        foreach Entry in Token.AsArray() do begin
            if Entries.Length() > 0 then
                Entries.Append(',');
            Entries.Append(TextValue(Entry.AsObject(), 'parameter') + ':' + TextValue(Entry.AsObject(), 'code'));
        end;
        exit(Entries.ToText());
    end;

    local procedure CreateReceipt(var ReceiptLine: Record "Warehouse Receipt Line"; Quantity: Decimal)
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ReceiptHeader: Record "Warehouse Receipt Header";
    begin
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, Quantity);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(ReceiptHeader, PurchaseHeader);
        ReceiptLine.SetRange("No.", ReceiptHeader."No.");
        ReceiptLine.FindFirst();
    end;

    local procedure CreateShipment(var ShipmentLine: Record "Warehouse Shipment Line"; Quantity: Decimal; RequirePick: Boolean)
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        if RequirePick then
            ShipmentHelper.SetupPickLocationAndItem(Location, Item, 100)
        else
            ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, Quantity);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        ShipmentLine.FindFirst();
    end;

    local procedure AssertReceiptUnchanged(ReceiptLine: Record "Warehouse Receipt Line"; Quantity: Decimal)
    var
        CurrentLine: Record "Warehouse Receipt Line";
        PostedReceiptHeader: Record "Posted Whse. Receipt Header";
    begin
        CurrentLine.Get(ReceiptLine."No.", ReceiptLine."Line No.");
        Assert.AreEqual(Quantity, CurrentLine."Qty. to Receive", 'Qty. to Receive must not change.');
        Assert.AreEqual(Quantity, CurrentLine."Qty. Outstanding", 'Nothing may be received.');
        PostedReceiptHeader.SetRange("Whse. Receipt No.", ReceiptLine."No.");
        Assert.RecordIsEmpty(PostedReceiptHeader);
    end;

    local procedure AssertGenericSetRefused(Subject: Text; RequestText: Text; ExpectedHintPart: Text)
    var
        ResponseJson: JsonObject;
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Data.Records.Set", Subject, RequestText, ResponseJson), 'Data.Records.Set should return JSON.');
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.IsTrue(TextValue(ResponseJson, 'nextStep').Contains(ExpectedHintPart), 'The next step must name ' + ExpectedHintPart + ': ' + ResponseText(ResponseJson));
    end;

    local procedure Run(MessageType: Enum "Message Type ori"; RequestText: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(MessageType, '', RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstEntry(Parent: JsonObject; Name: Text): JsonObject
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        Assert.IsTrue(Token.AsArray().Get(0, Token), Name + ' must have an entry.');
        exit(Token.AsObject());
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
    end;

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsValue().AsDecimal());
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
