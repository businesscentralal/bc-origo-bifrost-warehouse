namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>Issue #79: invalid paging is answered through the public dispatcher in both languages.</summary>
codeunit 97032 "Whse Negative Paging Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>AC01/AC02: Activity NegativeSkip in LCID 1033 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_Activity_NegativeSkip_1033()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.Activity.Get", 1033, '{"skip":-1}', 'skip');
    end;

    /// <summary>AC01/AC02: Activity NegativeTake in LCID 1033 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_Activity_NegativeTake_1033()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.Activity.Get", 1033, '{"take":-1}', 'take');
    end;

    /// <summary>AC01/AC02: Activity BothNegative in LCID 1033 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_Activity_BothNegative_1033()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.Activity.Get", 1033, '{"skip":-1,"take":-1}', 'skip,take');
    end;

    /// <summary>AC01/AC02: Activity NegativeSkip in LCID 1039 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_Activity_NegativeSkip_1039()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.Activity.Get", 1039, '{"skip":-1}', 'skip');
    end;

    /// <summary>AC01/AC02: Activity NegativeTake in LCID 1039 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_Activity_NegativeTake_1039()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.Activity.Get", 1039, '{"take":-1}', 'take');
    end;

    /// <summary>AC01/AC02: Activity BothNegative in LCID 1039 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_Activity_BothNegative_1039()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.Activity.Get", 1039, '{"skip":-1,"take":-1}', 'skip,take');
    end;

    /// <summary>AC01/AC02: BinContent NegativeSkip in LCID 1033 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_BinContent_NegativeSkip_1033()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.BinContent.Get", 1033, '{"skip":-1}', 'skip');
    end;

    /// <summary>AC01/AC02: BinContent NegativeTake in LCID 1033 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_BinContent_NegativeTake_1033()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.BinContent.Get", 1033, '{"take":-1}', 'take');
    end;

    /// <summary>AC01/AC02: BinContent BothNegative in LCID 1033 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_BinContent_BothNegative_1033()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.BinContent.Get", 1033, '{"skip":-1,"take":-1}', 'skip,take');
    end;

    /// <summary>AC01/AC02: BinContent NegativeSkip in LCID 1039 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_BinContent_NegativeSkip_1039()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.BinContent.Get", 1039, '{"skip":-1}', 'skip');
    end;

    /// <summary>AC01/AC02: BinContent NegativeTake in LCID 1039 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_BinContent_NegativeTake_1039()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.BinContent.Get", 1039, '{"take":-1}', 'take');
    end;

    /// <summary>AC01/AC02: BinContent BothNegative in LCID 1039 returns declared structured paging errors.</summary>
    [Test]
    procedure AC02_BinContent_BothNegative_1039()
    begin
        AssertNegativePaging("Message Type ori"::"Warehouse.BinContent.Get", 1039, '{"skip":-1,"take":-1}', 'skip,take');
    end;

    /// <summary>F1: Activity TextTake in LCID 1033 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_Activity_TextTake_1033()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.Activity.Get", 1033, '{"take":"abc"}', 'take', 'take', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: Activity DecimalSkip in LCID 1033 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_Activity_DecimalSkip_1033()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.Activity.Get", 1033, '{"skip":1.5}', 'skip', 'skip', '1.5');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: Activity MixedPaging in LCID 1033 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_Activity_MixedPaging_1033()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.Activity.Get", 1033, '{"skip":"abc","take":-1}', 'skip,take', 'skip', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: Activity TextTake in LCID 1039 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_Activity_TextTake_1039()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.Activity.Get", 1039, '{"take":"abc"}', 'take', 'take', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: Activity DecimalSkip in LCID 1039 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_Activity_DecimalSkip_1039()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.Activity.Get", 1039, '{"skip":1.5}', 'skip', 'skip', '1.5');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: Activity MixedPaging in LCID 1039 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_Activity_MixedPaging_1039()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.Activity.Get", 1039, '{"skip":"abc","take":-1}', 'skip,take', 'skip', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: BinContent TextTake in LCID 1033 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_BinContent_TextTake_1033()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.BinContent.Get", 1033, '{"take":"abc"}', 'take', 'take', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: BinContent DecimalSkip in LCID 1033 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_BinContent_DecimalSkip_1033()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.BinContent.Get", 1033, '{"skip":1.5}', 'skip', 'skip', '1.5');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: BinContent MixedPaging in LCID 1033 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_BinContent_MixedPaging_1033()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.BinContent.Get", 1033, '{"skip":"abc","take":-1}', 'skip,take', 'skip', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: BinContent TextTake in LCID 1039 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_BinContent_TextTake_1039()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.BinContent.Get", 1039, '{"take":"abc"}', 'take', 'take', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: BinContent DecimalSkip in LCID 1039 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_BinContent_DecimalSkip_1039()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.BinContent.Get", 1039, '{"skip":1.5}', 'skip', 'skip', '1.5');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    /// <summary>F1: BinContent MixedPaging in LCID 1039 retains every collected paging error field.</summary>
    [Test]
    procedure Scenario_BinContent_MixedPaging_1039()
    begin
        // Scenario: Non-integer paging uses the collecting reader and its paging nextStep.
        // Given: A self-contained request; validation needs no warehouse records.
        // When: The public dispatcher handles the request with an explicit envelope language.
        // Then: Assert every code, parameter, received, expected and nextStep below.
        AssertInvalidPaging("Message Type ori"::"Warehouse.BinContent.Get", 1039, '{"skip":"abc","take":-1}', 'skip,take', 'skip', 'abc');
        // After: The helper restores the caller language; native test isolation rolls back dispatcher records.
    end;

    local procedure AssertNegativePaging(MessageType: Enum "Message Type ori"; LanguageId: Integer; RequestText: Text; ParameterNames: Text)
    begin
        AssertInvalidPaging(MessageType, LanguageId, RequestText, ParameterNames, '', '');
    end;

    local procedure AssertInvalidPaging(MessageType: Enum "Message Type ori"; LanguageId: Integer; RequestText: Text; ParameterNames: Text; FormatParameterName: Text; FormatReceived: Text)
    var
        Assert: Codeunit "Library Assert";
        ContractAssert: Codeunit "Whse Contract Assert ori";
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseText: Text;
        OriginalLanguage: Integer;
        EmptyTaskId: Guid;
        MessageId: Guid;
        ResponseTime: Duration;
        ResponseJson: JsonObject;
        Token: JsonToken;
        Errors: JsonArray;
        ParameterName: Text;
        Index: Integer;
    begin
        // Story #79 AC01/AC02 | Time: independent of Today/WorkDate | Risk: no warehouse fixture is needed for refusals.
        // [GIVEN] A request with one or two invalid paging values in the selected language.
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(LanguageId);
        RequestContent.AddText(RequestText);
        // [WHEN] The public dispatcher handles the request with the explicit envelope language.
        // Execute uses Foundation's configured default, even when the test changed GlobalLanguage.
        Clear(EmptyTaskId);
        Dispatcher.EnqueueAndProcess(MessageType, "Message Version ori"::"1.0", '', 'Warehouse negative paging tests',
            'text/json', RequestContent, EmptyTaskId, LanguageId, MessageId, ResponseContent, ResponseContentType, ResponseTime);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        ResponseJson.ReadFrom(ResponseText);
        // [THEN] Every refusal retains its parameter, received, expected and declared nextStep.
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), 'Paging must return an error answer.');
        // Foundation's canonical help contract is English, even for an Icelandic message.
        // Keep the exact localized nextStep assertions below and verify its canonical counterpart separately.
        if LanguageId = 1033 then
            ContractAssert.AssertAnswerAndErrorsDeclared(MessageType, ResponseJson)
        else begin
            Assert.IsTrue(ContractAssert.IsDeclared(MessageType, TextValue(ResponseJson, 'code'), ''), 'The top-level refusal code must be declared.');
            if FormatParameterName <> '' then
                Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameterFormat', 'Send a whole number of zero or more, or leave it out.'), 'The English counterpart of the localized format nextStep must be declared.');
            if (FormatParameterName = '') or ParameterNames.Contains(',') then
                Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameter', 'Send a whole number of zero or more, or leave it out.'), 'The English counterpart of the localized negative nextStep must be declared.');
        end;
        if ParameterNames.Contains(',') then begin
            Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), 'Both invalid values must be collected.');
            Assert.IsTrue(ResponseJson.Get('errors', Token), 'MultipleErrors must list the problems.');
            Errors := Token.AsArray();
            Assert.AreEqual(2, Errors.Count(), 'Exactly the two paging values failed.');
            Index := 0;
            foreach ParameterName in ParameterNames.Split(',') do begin
                Errors.Get(Index, Token);
                AssertPagingError(Token.AsObject(), ParameterName, LanguageId, FormatParameterName, FormatReceived);
                Index += 1;
            end;
        end else
            AssertPagingError(ResponseJson, ParameterNames, LanguageId, FormatParameterName, FormatReceived);
        GlobalLanguage(OriginalLanguage);
    end;

    local procedure AssertPagingError(ErrorJson: JsonObject; ParameterName: Text; LanguageId: Integer; FormatParameterName: Text; FormatReceived: Text)
    var
        Assert: Codeunit "Library Assert";
    begin
        if ParameterName = FormatParameterName then begin
            Assert.AreEqual('InvalidParameterFormat', TextValue(ErrorJson, 'code'), 'A non-integer value is InvalidParameterFormat.');
            Assert.AreEqual(FormatReceived, TextValue(ErrorJson, 'received'), 'The refusal must retain the supplied non-integer value.');
            Assert.AreEqual('integer', TextValue(ErrorJson, 'expected'), 'The format refusal must require an integer in either language.');
        end else begin
            Assert.AreEqual('InvalidParameter', TextValue(ErrorJson, 'code'), 'A negative value is InvalidParameter.');
            Assert.AreEqual('-1', TextValue(ErrorJson, 'received'), 'The refusal must retain the supplied value.');
            if LanguageId = 1039 then
                Assert.AreEqual('núll eða stærra', TextValue(ErrorJson, 'expected'), 'The expected range must be Icelandic.')
            else
                Assert.AreEqual('zero or greater', TextValue(ErrorJson, 'expected'), 'The expected range must be explicit.');
        end;
        Assert.AreEqual(ParameterName, TextValue(ErrorJson, 'parameter'), 'The refusal must name the paging key.');
        Assert.AreNotEqual('', TextValue(ErrorJson, 'error'), 'The refusal must explain the problem.');
        if LanguageId = 1039 then begin
            Assert.AreEqual('Sendu heiltölu sem er núll eða stærri, eða slepptu því.', TextValue(ErrorJson, 'nextStep'), 'The nextStep must match the Icelandic help.');
        end else begin
            Assert.AreEqual('Send a whole number of zero or more, or leave it out.', TextValue(ErrorJson, 'nextStep'), 'The nextStep must match the English help.');
        end;
    end;
    local procedure TextValue(Value: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if Value.Get(KeyName, Token) then
            if Token.IsValue() then
                exit(Token.AsValue().AsText());
        exit('');
    end;
}
