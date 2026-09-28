namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Activity.Get through the public Foundation dispatcher.
/// </summary>
codeunit 97001 "Whse Activity Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = codeunit "Whse Activity Get Impl ori" = X;

    /// <summary>Verifies that lookup by number returns the activity header and requested lines.</summary>
    [Test]
    procedure GetByNumberReturnsHeaderAndLines()
    var
        Assert: Codeunit "Library Assert";
        TestData: Codeunit "Whse Test Data ori";
        ActivityType: Enum "Warehouse Activity Type";
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        LinesArray: JsonArray;
        Token: JsonToken;
    begin
        TestData.CreateActivity(ActivityType::Pick, 'WHSE-TEST-001', 'WHITE', '', 'DOC-TEST-001');

        ExecuteActivityGet('{"no":"WHSE-TEST-001","includeLines":true}', '', ResponseJson);

        Assert.IsTrue(GetTextProperty(ResponseJson, 'status') = 'Success', 'The activity lookup should succeed.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The response should contain results.');
        ResultArray := Token.AsArray();
        Assert.IsTrue(ResultArray.Count() = 1, 'The activity lookup should return one header.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The first result should exist.');
        Assert.IsTrue(Token.AsObject().Get('no', Token), 'The activity number should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'WHSE-TEST-001', 'The activity number should match.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The first result should exist.');
        Assert.IsTrue(Token.AsObject().Get('activityType', Token), 'The activity type should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'Pick', 'The activity type should be serialized by its enum name.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The first result should exist.');
        Assert.IsTrue(Token.AsObject().Get('lines', Token), 'The requested line array should be present.');
        LinesArray := Token.AsArray();
        Assert.IsTrue(LinesArray.Count() = 1, 'The activity should return its line.');
        Assert.IsTrue(LinesArray.Get(0, Token), 'The first activity line should exist.');
        Assert.IsTrue(Token.AsObject().Get('whseDocumentNo', Token), 'The line document number should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'DOC-TEST-001', 'The line document number should match.');
    end;

    /// <summary>Verifies that an unknown activity number returns a structured error.</summary>
    [Test]
    procedure MissingNumberReturnsStructuredError()
    var
        Assert: Codeunit "Library Assert";
        ResponseJson: JsonObject;
    begin
        ExecuteActivityGet('{"no":"DOES-NOT-EXIST"}', '', ResponseJson);

        Assert.IsTrue(GetTextProperty(ResponseJson, 'status') = 'Error', 'A missing activity number should return a structured error.');
        Assert.IsTrue(GetTextProperty(ResponseJson, 'code') = 'RecordNotFound', 'A missing activity number should return RecordNotFound.');
        Assert.IsTrue(GetTextProperty(ResponseJson, 'parameter') = 'no', 'A missing activity number should name the no parameter.');
    end;

    /// <summary>Verifies that an unknown activity SystemId returns a structured error.</summary>
    [Test]
    procedure MissingSystemIdReturnsStructuredError()
    var
        Assert: Codeunit "Library Assert";
        ResponseJson: JsonObject;
    begin
        ExecuteActivityGet('{"systemId":"00000000-0000-0000-0000-000000000000"}', '', ResponseJson);

        Assert.IsTrue(GetTextProperty(ResponseJson, 'status') = 'Error', 'A missing activity SystemId should return a structured error.');
        Assert.IsTrue(GetTextProperty(ResponseJson, 'code') = 'RecordNotFound', 'A missing activity SystemId should return RecordNotFound.');
        Assert.IsTrue(GetTextProperty(ResponseJson, 'parameter') = 'systemId', 'A missing activity SystemId should name the systemId parameter.');
    end;

    /// <summary>Verifies that activity type, document, location, and assigned-user filters combine.</summary>
    [Test]
    procedure FiltersByActivityTypeDocumentLocationAndAssignedUser()
    var
        Assert: Codeunit "Library Assert";
        TestData: Codeunit "Whse Test Data ori";
        ActivityType: Enum "Warehouse Activity Type";
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        Token: JsonToken;
    begin
        TestData.CreateActivity(ActivityType::Pick, 'WHSE-FILTER-001', 'WHITE', '', 'DOC-FILTER-001');
        TestData.CreateActivity(ActivityType::Pick, 'WHSE-FILTER-002', 'WHITE', 'ALICE', 'DOC-FILTER-001');
        TestData.CreateActivity(ActivityType::"Put-away", 'WHSE-FILTER-003', 'WHITE', '', 'DOC-FILTER-001');
        TestData.CreateActivity(ActivityType::Pick, 'WHSE-FILTER-004', 'BLUE', '', 'DOC-FILTER-001');

        ExecuteActivityGet(
            '{"activityType":"Pick","whseDocumentNo":"DOC-FILTER-001","locationCode":"WHITE","assignedUserId":""}',
            '',
            ResponseJson);

        Assert.IsTrue(GetTextProperty(ResponseJson, 'status') = 'Success', 'The filtered activity query should succeed.');
        Assert.IsTrue(GetIntegerProperty(ResponseJson, 'noOfRecords') = 1, 'Only the fully matching activity should be counted.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The response should contain results.');
        ResultArray := Token.AsArray();
        Assert.IsTrue(ResultArray.Count() = 1, 'Only the fully matching activity should be returned.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The matching activity should exist.');
        Assert.IsTrue(Token.AsObject().Get('no', Token), 'The activity number should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'WHSE-FILTER-001', 'The returned activity should match every filter.');
    end;

    /// <summary>Verifies that skip and take page activity headers without changing the total count.</summary>
    [Test]
    procedure PagesHeadersAndReportsUnpagedCount()
    var
        Assert: Codeunit "Library Assert";
        TestData: Codeunit "Whse Test Data ori";
        ActivityType: Enum "Warehouse Activity Type";
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        Token: JsonToken;
    begin
        TestData.CreateActivityHeader(ActivityType::Pick, 'WHSE-PAGE-001', 'WHITE', 'ALICE');
        TestData.CreateActivityHeader(ActivityType::Pick, 'WHSE-PAGE-002', 'WHITE', 'ALICE');

        ExecuteActivityGet('{"skip":1,"take":1}', '', ResponseJson);

        Assert.IsTrue(GetIntegerProperty(ResponseJson, 'noOfRecords') = 2, 'The count should include both matching headers.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The response should contain results.');
        ResultArray := Token.AsArray();
        Assert.IsTrue(ResultArray.Count() = 1, 'The requested page should contain one header.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The page entry should exist.');
        Assert.IsTrue(Token.AsObject().Get('no', Token), 'The page entry number should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'WHSE-PAGE-002', 'Skip should advance to the second header.');
    end;

    /// <summary>Verifies that IsEnabled is false when the caller cannot read warehouse activities.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutReadPermission()
    var
        Assert: Codeunit "Library Assert";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Activity.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Activity.Get must be disabled without read permission on Warehouse Activity Header.');
    end;

    local procedure ExecuteActivityGet(RequestText: Text; Subject: Text[250]; var ResponseJson: JsonObject)
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[50];
        ResponseText: Text;
    begin
        RequestContent.AddText(RequestText);
        Dispatcher.Execute(
            Enum::"Message Type ori"::"Warehouse.Activity.Get",
            Enum::"Message Version ori"::"1.0",
            Subject,
            'Warehouse Activity Get Tests',
            'text/json',
            RequestContent,
            ResponseContent,
            ResponseContentType);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        ResponseJson.ReadFrom(ResponseText);
    end;

    local procedure GetTextProperty(ResponseJson: JsonObject; PropertyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not ResponseJson.Get(PropertyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure GetIntegerProperty(ResponseJson: JsonObject; PropertyName: Text): Integer
    var
        Token: JsonToken;
    begin
        if not ResponseJson.Get(PropertyName, Token) then
            exit(-1);
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsInteger());
    end;
}
