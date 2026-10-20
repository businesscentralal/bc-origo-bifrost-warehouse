namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;
using Microsoft.Warehouse.Setup;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.RegisteredActivity.Get (#58) through the public dispatcher, on registered activity fixtures.
/// </summary>
codeunit 97045 "Whse RegActivity Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";

    /// <summary>AC03: a registered pick is found by source number with lines, and by number.</summary>
    [Test]
    procedure Get_RegisteredPick_BySourceNoAndNo()
    var
        ResponseJson: JsonObject;
        Activity: JsonObject;
        Line: JsonObject;
        ActivityNo: Code[20];
        SourceNo: Code[20];
    begin
        // Story #58, AC03 | Time: fixed registering date 2026-10-19 | Risk: fixtures, not a registering run.
        ActivityNo := NewCode('RPI');
        SourceNo := NewCode('SO');
        CreateRegistered(Enum::"Warehouse Activity Type"::Pick, ActivityNo, 'DOCFLOW', SourceNo, 20261019D);

        Run('{"activityType":"Pick","sourceNo":"' + SourceNo + '","includeLines":true}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Pick', TextValue(ResponseJson, 'activityType'), 'activityType');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'One registered pick has the source number.');
        Activity := FirstEntry(ResponseJson, 'result');
        Assert.AreEqual(ActivityNo, TextValue(Activity, 'no'), 'no');
        Assert.AreEqual('2026-10-19', TextValue(Activity, 'registeringDate'), 'registeringDate');
        Line := FirstEntry(Activity, 'lines');
        Assert.AreEqual('Take', TextValue(Line, 'actionType'), 'actionType');
        Assert.AreEqual(SourceNo, TextValue(Line, 'sourceNo'), 'sourceNo');
        Assert.AreEqual('Shipment', TextValue(Line, 'whseDocumentType'), 'whseDocumentType');

        Run('{"activityType":"pick","no":"' + ActivityNo + '"}', '', ResponseJson);
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'no names one registered pick.');
    end;

    /// <summary>AC03: putAway and movement are separate activity types, and the registering date range filters.</summary>
    [Test]
    procedure Get_PutAway_ByTypeAndDate()
    var
        ResponseJson: JsonObject;
        ActivityNo: Code[20];
        LocationCode: Code[10];
    begin
        // Story #58, AC03 | Time: fixed registering date 2026-10-18 | Risk: fixtures, not a registering run.
        ActivityNo := NewCode('RPU');
        LocationCode := CopyStr(NewCode('L'), 1, MaxStrLen(LocationCode));
        CreateRegistered(Enum::"Warehouse Activity Type"::"Put-away", ActivityNo, LocationCode, NewCode('PO'), 20261018D);

        Run('{"activityType":"putAway","locationCode":"' + LocationCode + '","registeringDateFrom":"2026-10-18","registeringDateTo":"2026-10-18"}', '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'One registered put-away in the range.');

        Run('{"activityType":"Movement","locationCode":"' + LocationCode + '"}', '', ResponseJson);
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'noOfRecords'), 'The put-away is not a movement.');

        Run('{"activityType":"PutAway","locationCode":"' + LocationCode + '","registeringDateTo":"2026-10-17"}', '', ResponseJson);
        Assert.AreEqual(0, ArrayCount(ResponseJson, 'result'), 'The registering date is after the range.');
    end;

    /// <summary>AC04, AC05 and AC06: unknown activityType, unknown number, missing activityType, a bad date and an unknown key are refused.</summary>
    [Test]
    procedure Get_Refusals()
    var
        ResponseJson: JsonObject;
    begin
        // Story #58, AC04 + AC05 + AC06 | Time: independent of WorkDate | Risk: none.
        Run('{"activityType":"Count"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use one of the values listed in the help.', TextValue(ResponseJson, 'nextStep'), 'InvalidParameter next step.');

        Run('{"activityType":"Pick","no":"' + NewCode('NOPE') + '"}', '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Search with filters instead of a no.', TextValue(ResponseJson, 'nextStep'), 'RecordNotFound next step.');

        Run('{"no":"X"}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"activityType":"Pick","registeringDateFrom":20261019}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"activityType":"Pick","bin":"A"}', '', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    /// <summary>AC07: filters that match nothing answer success with an empty list.</summary>
    [Test]
    procedure Get_NoMatch_AnswersEmptyList()
    var
        ResponseJson: JsonObject;
    begin
        // Story #58, AC07 | Time: independent of WorkDate | Risk: none.
        Run('{"activityType":"Movement","sourceNo":"' + NewCode('NONE') + '"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(0, ArrayCount(ResponseJson, 'result'), 'Empty list.');
    end;

    /// <summary>AC08: without read permission the type is disabled and answers PermissionDenied naming the read set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Get_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RegActivityGetImpl: Codeunit "Whse RegActivity Get Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Story #58, AC08 | Time: independent of WorkDate | Risk: none.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.RegisteredActivity.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'The type must be disabled without read permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        RegActivityGetImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Read ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the read permission set.');
    end;

    local procedure CreateRegistered(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; LocationCode: Code[10]; SourceNo: Code[20]; RegisteringDate: Date)
    var
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        RegisteredLine: Record "Registered Whse. Activity Line";
    begin
        RegisteredHeader.Init();
        RegisteredHeader.Type := ActivityType;
        RegisteredHeader."No." := ActivityNo;
        RegisteredHeader."Location Code" := LocationCode;
        RegisteredHeader."Registering Date" := RegisteringDate;
        RegisteredHeader.Insert(false);
        RegisteredLine.Init();
        RegisteredLine."Activity Type" := ActivityType;
        RegisteredLine."No." := ActivityNo;
        RegisteredLine."Line No." := 10000;
        RegisteredLine."Source Type" := 37;
        RegisteredLine."Source Subtype" := 1;
        RegisteredLine."Source No." := SourceNo;
        RegisteredLine."Source Line No." := 10000;
        RegisteredLine."Source Document" := Enum::"Warehouse Activity Source Document"::"Sales Order";
        RegisteredLine."Location Code" := LocationCode;
        RegisteredLine."Item No." := 'DOCFLOW-ITEM';
        RegisteredLine.Quantity := 3;
        RegisteredLine."Unit of Measure Code" := 'PCS';
        RegisteredLine."Action Type" := Enum::"Warehouse Action Type"::Take;
        RegisteredLine."Whse. Document Type" := Enum::"Warehouse Activity Document Type"::Shipment;
        RegisteredLine."Whse. Document No." := 'SH-DOCFLOW';
        RegisteredLine.Insert(false);
    end;

    local procedure NewCode(Prefix: Text): Code[20]
    begin
        exit(CopyStr(UpperCase(Prefix + DelChr(Format(CreateGuid()), '=', '{}-')), 1, 10));
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.RegisteredActivity.Get", Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
