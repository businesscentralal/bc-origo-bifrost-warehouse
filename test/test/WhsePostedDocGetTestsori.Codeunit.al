namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.History;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.PostedDocument.Get (#58) through the public dispatcher, on posted warehouse document fixtures.
/// </summary>
codeunit 97044 "Whse PostedDoc Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";

    /// <summary>AC02: a posted receipt is found by source number with its lines, and by its number.</summary>
    [Test]
    procedure Get_PostedReceipt_BySourceNoAndNo()
    var
        ResponseJson: JsonObject;
        Document: JsonObject;
        Line: JsonObject;
        DocumentNo: Code[20];
        SourceNo: Code[20];
    begin
        // Story #58, AC02 | Time: fixed posting date 2026-10-19 | Risk: fixtures, not a posting run.
        DocumentNo := NewCode('PWR');
        SourceNo := NewCode('PO');
        CreatePostedReceipt(DocumentNo, 'DOCFLOW', SourceNo, 20261019D);

        Run('{"documentType":"Receipt","sourceNo":"' + SourceNo + '","includeLines":true}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Receipt', TextValue(ResponseJson, 'documentType'), 'documentType');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'One posted receipt has the source number.');
        Document := FirstEntry(ResponseJson, 'result');
        Assert.AreEqual(DocumentNo, TextValue(Document, 'no'), 'no');
        Assert.AreEqual('2026-10-19', TextValue(Document, 'postingDate'), 'postingDate');
        Line := FirstEntry(Document, 'lines');
        Assert.AreEqual('Purchase Order', TextValue(Line, 'sourceDocument'), 'sourceDocument');
        Assert.AreEqual(SourceNo, TextValue(Line, 'sourceNo'), 'sourceNo');
        Assert.AreEqual('Posted Receipt', TextValue(Line, 'postedSourceDocument'), 'postedSourceDocument');

        Run('{"documentType":"receipt"}', DocumentNo, ResponseJson);
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'The subject names one posted receipt.');
        Assert.IsFalse(FirstEntry(ResponseJson, 'result').Contains('lines'), 'Lines only with includeLines.');
    end;

    /// <summary>AC02: a posted shipment is found by location and posting date range.</summary>
    [Test]
    procedure Get_PostedShipment_ByLocationAndDate()
    var
        ResponseJson: JsonObject;
        DocumentNo: Code[20];
        LocationCode: Code[10];
    begin
        // Story #58, AC02 | Time: fixed posting date 2026-10-18 | Risk: fixtures, not a posting run.
        DocumentNo := NewCode('PWS');
        LocationCode := CopyStr(NewCode('L'), 1, MaxStrLen(LocationCode));
        CreatePostedShipment(DocumentNo, LocationCode, NewCode('SO'), 20261018D);

        Run('{"documentType":"Shipment","locationCode":"' + LocationCode + '","postingDateFrom":"2026-10-18","postingDateTo":"2026-10-18"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'One posted shipment in the range.');
        Assert.AreEqual(DocumentNo, TextValue(FirstEntry(ResponseJson, 'result'), 'no'), 'no');

        Run('{"documentType":"Shipment","locationCode":"' + LocationCode + '","postingDateFrom":"2026-10-19"}', '', ResponseJson);
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'noOfRecords'), 'The posting date is before the range.');
    end;

    /// <summary>AC07: filters that match nothing answer success with an empty list.</summary>
    [Test]
    procedure Get_NoMatch_AnswersEmptyList()
    var
        ResponseJson: JsonObject;
    begin
        // Story #58, AC07 | Time: independent of WorkDate | Risk: none.
        Run('{"documentType":"Receipt","sourceNo":"' + NewCode('NONE') + '"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(0, ArrayCount(ResponseJson, 'result'), 'Empty list.');
    end;

    /// <summary>AC04, AC05 and AC06: unknown documentType, unknown number, missing documentType and unknown key are refused.</summary>
    [Test]
    procedure Get_Refusals()
    var
        ResponseJson: JsonObject;
    begin
        // Story #58, AC04 + AC05 + AC06 | Time: independent of WorkDate | Risk: none.
        Run('{"documentType":"Invoice"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use one of the values listed in the help.', TextValue(ResponseJson, 'nextStep'), 'InvalidParameter next step.');

        Run('{"documentType":"Receipt","no":"' + NewCode('NOPE') + '"}', '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Search with filters instead of a no.', TextValue(ResponseJson, 'nextStep'), 'RecordNotFound next step.');

        Run('{}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"documentType":"Receipt","includeLines":"yes"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"documentType":"Receipt","page":2}', '', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"documentType":"Receipt","no":"A-1"}', 'B-2', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    /// <summary>AC08: without read permission the type is disabled and answers PermissionDenied naming the read set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Get_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        PostedDocGetImpl: Codeunit "Whse PostedDoc Get Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Story #58, AC08 | Time: independent of WorkDate | Risk: none.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.PostedDocument.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'The type must be disabled without read permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        PostedDocGetImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Read ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the read permission set.');
    end;

    local procedure CreatePostedReceipt(DocumentNo: Code[20]; LocationCode: Code[10]; SourceNo: Code[20]; PostingDate: Date)
    var
        ReceiptHeader: Record "Posted Whse. Receipt Header";
        ReceiptLine: Record "Posted Whse. Receipt Line";
    begin
        ReceiptHeader.Init();
        ReceiptHeader."No." := DocumentNo;
        ReceiptHeader."Location Code" := LocationCode;
        ReceiptHeader."Posting Date" := PostingDate;
        ReceiptHeader.Insert(false);
        ReceiptLine.Init();
        ReceiptLine."No." := DocumentNo;
        ReceiptLine."Line No." := 10000;
        ReceiptLine."Source Type" := 39;
        ReceiptLine."Source Subtype" := 1;
        ReceiptLine."Source No." := SourceNo;
        ReceiptLine."Source Line No." := 10000;
        ReceiptLine."Source Document" := Enum::"Warehouse Activity Source Document"::"Purchase Order";
        ReceiptLine."Location Code" := LocationCode;
        ReceiptLine."Item No." := 'DOCFLOW-ITEM';
        ReceiptLine.Quantity := 5;
        ReceiptLine."Unit of Measure Code" := 'PCS';
        ReceiptLine."Posted Source Document" := ReceiptLine."Posted Source Document"::"Posted Receipt";
        ReceiptLine."Posted Source No." := CopyStr('R' + SourceNo, 1, MaxStrLen(ReceiptLine."Posted Source No."));
        ReceiptLine.Insert(false);
    end;

    local procedure CreatePostedShipment(DocumentNo: Code[20]; LocationCode: Code[10]; SourceNo: Code[20]; PostingDate: Date)
    var
        ShipmentHeader: Record "Posted Whse. Shipment Header";
        ShipmentLine: Record "Posted Whse. Shipment Line";
    begin
        ShipmentHeader.Init();
        ShipmentHeader."No." := DocumentNo;
        ShipmentHeader."Location Code" := LocationCode;
        ShipmentHeader."Posting Date" := PostingDate;
        ShipmentHeader.Insert(false);
        ShipmentLine.Init();
        ShipmentLine."No." := DocumentNo;
        ShipmentLine."Line No." := 10000;
        ShipmentLine."Source Type" := 37;
        ShipmentLine."Source Subtype" := 1;
        ShipmentLine."Source No." := SourceNo;
        ShipmentLine."Source Line No." := 10000;
        ShipmentLine."Source Document" := Enum::"Warehouse Activity Source Document"::"Sales Order";
        ShipmentLine."Location Code" := LocationCode;
        ShipmentLine."Item No." := 'DOCFLOW-ITEM';
        ShipmentLine.Quantity := 2;
        ShipmentLine."Unit of Measure Code" := 'PCS';
        ShipmentLine.Insert(false);
    end;

    local procedure NewCode(Prefix: Text): Code[20]
    begin
        exit(CopyStr(UpperCase(Prefix + DelChr(Format(CreateGuid()), '=', '{}-')), 1, 10));
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.PostedDocument.Get", Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
