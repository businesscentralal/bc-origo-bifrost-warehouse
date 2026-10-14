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
        TestData.CreateActivityHeader(ActivityType::Pick, 'WHSE-PAGE-001', 'PAGELC', 'PAGEUSER');
        TestData.CreateActivityHeader(ActivityType::Pick, 'WHSE-PAGE-002', 'PAGELC', 'PAGEUSER');

        ExecuteActivityGet('{"locationCode":"PAGELC","assignedUserId":"PAGEUSER","skip":1,"take":1}', '', ResponseJson);

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
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');

        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Activity.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Activity.Get must be disabled without read permission on Warehouse Activity Header.');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC01_NoAndSystemId_RejectConflict.</summary>
    [Test]
    procedure Scenario_AC01_NoAndSystemId_RejectConflict()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"no":"XWH37-A","systemId":"' + Format(ActivityHeader.SystemId, 0, 4) + '"}', '', ResponseJson);
        AssertConflict(ResponseJson, 'no', 'systemId');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC01_SubjectAndSystemId_RejectConflict.</summary>
    [Test]
    procedure Scenario_AC01_SubjectAndSystemId_RejectConflict()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"systemId":"' + Format(ActivityHeader.SystemId, 0, 4) + '"}', 'XWH37-A', ResponseJson);
        AssertConflict(ResponseJson, 'subject', 'systemId');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC01_NoAndSubject_RejectConflict.</summary>
    [Test]
    procedure Scenario_AC01_NoAndSubject_RejectConflict()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"no":"XWH37-A"}', 'XWH37-B', ResponseJson);
        AssertConflict(ResponseJson, 'subject', 'no');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC01_Aliases_RejectConflict.</summary>
    [Test]
    procedure Scenario_AC01_Aliases_RejectConflict()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"activityNo":"XWH37-A","id":"' + Format(ActivityHeader.SystemId, 0, 4) + '"}', '', ResponseJson);
        AssertConflict(ResponseJson, 'activityNo', 'id');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC02_AllIdentifiers_ReturnOneRecord.</summary>
    [Test]
    procedure Scenario_AC02_AllIdentifiers_ReturnOneRecord()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        RequestJson: JsonObject;
        RequestText: Text;
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        RequestJson.Add('no', ActivityHeader."No.");
        RequestJson.Add('activityNo', ActivityHeader."No.");
        RequestJson.Add('systemId', Format(ActivityHeader.SystemId, 0, 4));
        RequestJson.Add('id', Format(ActivityHeader.SystemId, 0, 4));
        RequestJson.Add('recordSystemId', Format(ActivityHeader.SystemId, 0, 4));
        RequestJson.WriteTo(RequestText);
        ExecuteActivityGet(RequestText, ActivityHeader."No.", ResponseJson);
        AssertSingleActivity(ResponseJson, ActivityHeader."No.");
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC03_ActivityNo_ReturnRecord.</summary>
    [Test]
    procedure Scenario_AC03_ActivityNo_ReturnRecord()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"activityNo":"XWH37-A"}', '', ResponseJson);
        AssertSingleActivity(ResponseJson, 'XWH37-A');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC03_UnknownAlias_ReturnNotFound.</summary>
    [Test]
    procedure Scenario_AC03_UnknownAlias_ReturnNotFound()
    var
        ResponseJson: JsonObject;
    begin
        ExecuteActivityGet('{"activityNo":"XWH37-MISSING"}', '', ResponseJson);
        AssertErrorResponse(ResponseJson, 'RecordNotFound', 'activityNo');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC04_id_ReturnRecord.</summary>
    [Test]
    procedure Scenario_AC04_id_ReturnRecord()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"id":"' + Format(ActivityHeader.SystemId, 0, 4) + '"}', '', ResponseJson);
        AssertSingleActivity(ResponseJson, 'XWH37-B');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC04_id_RejectNonGuid.</summary>
    [Test]
    procedure Scenario_AC04_id_RejectNonGuid()
    var
        ResponseJson: JsonObject;
    begin
        ExecuteActivityGet('{"id":"not-a-guid"}', '', ResponseJson);
        AssertErrorResponse(ResponseJson, 'InvalidParameterFormat', 'id');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC04_recordSystemId_ReturnRecord.</summary>
    [Test]
    procedure Scenario_AC04_recordSystemId_ReturnRecord()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"recordSystemId":"' + Format(ActivityHeader.SystemId, 0, 4) + '"}', '', ResponseJson);
        AssertSingleActivity(ResponseJson, 'XWH37-B');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC04_recordSystemId_RejectNonGuid.</summary>
    [Test]
    procedure Scenario_AC04_recordSystemId_RejectNonGuid()
    var
        ResponseJson: JsonObject;
    begin
        ExecuteActivityGet('{"recordSystemId":"not-a-guid"}', '', ResponseJson);
        AssertErrorResponse(ResponseJson, 'InvalidParameterFormat', 'recordSystemId');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC04_InvalidAliasWithNo_RejectFormat.</summary>
    [Test]
    procedure Scenario_AC04_InvalidAliasWithNo_RejectFormat()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"no":"XWH37-A","id":"not-a-guid"}', '', ResponseJson);
        AssertErrorResponse(ResponseJson, 'InvalidParameterFormat', 'id');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC05_AliasesWithFilter_NoUnrelatedRow.</summary>
    [Test]
    procedure Scenario_AC05_AliasesWithFilter_NoUnrelatedRow()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        CreateIdentifierFixtures(ActivityHeader);
        ExecuteActivityGet('{"activityNo":"XWH37-A","locationCode":"XWH37-B"}', '', ResponseJson);
        AssertErrorResponse(ResponseJson, 'RecordNotFound', 'systemId');
        ExecuteActivityGet('{"id":"' + Format(ActivityHeader.SystemId, 0, 4) + '","locationCode":"XWH37-B"}', '', ResponseJson);
        AssertSingleActivity(ResponseJson, 'XWH37-B');
        ExecuteActivityGet('{"recordSystemId":"' + Format(ActivityHeader.SystemId, 0, 4) + '","locationCode":"XWH37-A"}', '', ResponseJson);
        AssertErrorResponse(ResponseJson, 'RecordNotFound', 'systemId');
    end;

    /// <summary>Regression for warehouse#37: Scenario_AC06_BilingualHelp_DeclaresContract.</summary>
    [Test]
    procedure Scenario_AC06_BilingualHelp_DeclaresContract()
    var
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        AssertIdentifierHelp(1033);
        AssertIdentifierHelp(1039);
        GlobalLanguage(OriginalLanguage);
    end;

    local procedure CreateIdentifierFixtures(var ActivityHeader: Record "Warehouse Activity Header")
    var
        TestData: Codeunit "Whse Test Data ori";
    begin
        TestData.CreateActivityHeader(Enum::"Warehouse Activity Type"::Pick, 'XWH37-A', 'XWH37-A', '');
        TestData.CreateActivityHeader(Enum::"Warehouse Activity Type"::Pick, 'XWH37-B', 'XWH37-B', '');
        ActivityHeader.Get(Enum::"Warehouse Activity Type"::Pick, 'XWH37-B');
    end;

    local procedure AssertSingleActivity(ResponseJson: JsonObject; ExpectedNo: Text)
    var
        Assert: Codeunit "Library Assert";
        Token: JsonToken;
        Results: JsonArray;
    begin
        Assert.AreEqual('Success', GetTextProperty(ResponseJson, 'status'), 'The identifier lookup must succeed.');
        Assert.AreEqual(1, GetIntegerProperty(ResponseJson, 'noOfRecords'), 'Exactly the identified record must match.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The result array must be present.');
        Results := Token.AsArray();
        Assert.AreEqual(1, Results.Count(), 'Exactly one record must be returned.');
        Results.Get(0, Token);
        Assert.AreEqual(ExpectedNo, GetTextProperty(Token.AsObject(), 'no'), 'An unrelated activity must never be returned.');
    end;

    local procedure AssertErrorResponse(ResponseJson: JsonObject; ExpectedCode: Text; ExpectedParameter: Text)
    var
        Assert: Codeunit "Library Assert";
        Token: JsonToken;
    begin
        Assert.AreEqual('Error', GetTextProperty(ResponseJson, 'status'), 'The request must return a structured error.');
        Assert.AreEqual(ExpectedCode, GetTextProperty(ResponseJson, 'code'), 'The stable error code must match.');
        Assert.AreEqual(ExpectedParameter, GetTextProperty(ResponseJson, 'parameter'), 'The error must name the source parameter.');
        Assert.IsFalse(ResponseJson.Get('result', Token), 'Errors must not return activity records.');
    end;

    local procedure AssertConflict(ResponseJson: JsonObject; FirstParameter: Text; SecondParameter: Text)
    var
        Assert: Codeunit "Library Assert";
    begin
        AssertErrorResponse(ResponseJson, 'ConflictingIdentifiers', SecondParameter);
        Assert.IsTrue(GetTextProperty(ResponseJson, 'error').Contains(FirstParameter), 'The conflict must name the first parameter.');
        Assert.IsTrue(GetTextProperty(ResponseJson, 'error').Contains(SecondParameter), 'The conflict must name the second parameter.');
        Assert.IsTrue(GetTextProperty(ResponseJson, 'nextStep') <> '', 'Conflicts must describe how to correct the request.');
    end;

    local procedure AssertIdentifierHelp(LanguageId: Integer)
    var
        Assert: Codeunit "Library Assert";
        Contract: Interface "Msg Contract ori";
        Errors: JsonArray;
        Targets: JsonArray;
        Entry: JsonToken;
        ErrorJson: JsonObject;
        TargetText: Text;
        FoundConflict: Boolean;
    begin
        GlobalLanguage(LanguageId);
        Contract := Enum::"Message Type ori"::"Warehouse.Activity.Get";
        Assert.IsTrue(Contract.GetErrors(Errors), 'Help must declare errors in both languages.');
        foreach Entry in Errors do begin
            ErrorJson := Entry.AsObject();
            if GetTextProperty(ErrorJson, 'code') = 'ConflictingIdentifiers' then begin
                FoundConflict := true;
                Assert.IsTrue(GetTextProperty(ErrorJson, 'when') <> '', 'Conflict help must describe when it occurs.');
                Assert.IsTrue(GetTextProperty(ErrorJson, 'nextStep') <> '', 'Conflict help must describe the next step.');
            end;
        end;
        Assert.IsTrue(FoundConflict, 'Help must declare ConflictingIdentifiers.');
        Assert.IsTrue(Contract.GetTarget(Targets), 'Help must declare the target aliases.');
        Targets.WriteTo(TargetText);
        Assert.IsTrue(TargetText.Contains('data.activityNo'), 'Help must declare the activityNo alias.');
        Assert.IsTrue(TargetText.Contains('data.id'), 'Help must declare the id alias.');
        Assert.IsTrue(TargetText.Contains('data.recordSystemId'), 'Help must declare the recordSystemId alias.');
    end;

    local procedure ExecuteActivityGet(RequestText: Text; Subject: Text[250]; var ResponseJson: JsonObject)
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
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
