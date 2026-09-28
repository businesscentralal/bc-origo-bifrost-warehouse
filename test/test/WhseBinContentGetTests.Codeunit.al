namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.BinContent.Get through the public Foundation dispatcher.
/// </summary>
codeunit 97000 "Whse BinContent Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>Verifies that exact convenience filters return the matching bin content.</summary>
    [Test]
    procedure GetReturnsMatchingBinContent()
    var
        Assert: Codeunit "Library Assert";
        TestData: Codeunit "Whse Test Data ori";
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        Token: JsonToken;
    begin
        TestData.CreateBinContent('WH-TEST', 'BIN-01', 'ITEM-01', 'BLUE', 'PCS');
        TestData.CreateBinContent('WH-TEST', 'BIN-02', 'ITEM-01', 'BLUE', 'PCS');

        ExecuteBinContentGet(
            '{"locationCode":"WH-TEST","binCode":"BIN-01","itemNo":"ITEM-01","variantCode":"BLUE"}',
            ResponseJson);

        Assert.IsTrue(GetTextProperty(ResponseJson, 'status') = 'Success', 'The bin content query should succeed.');
        Assert.IsTrue(GetIntegerProperty(ResponseJson, 'noOfRecords') = 1, 'Only the matching bin content should be counted.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The response should contain results.');
        ResultArray := Token.AsArray();
        Assert.IsTrue(ResultArray.Count() = 1, 'Only the matching bin content should be returned.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The matching bin content should exist.');
        Assert.IsTrue(Token.AsObject().Get('binCode', Token), 'The bin code should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'BIN-01', 'The returned bin should match the filter.');
    end;

    /// <summary>Verifies that paging applies to rows while the count remains unpaged.</summary>
    [Test]
    procedure GetPagesRowsAndReportsUnpagedCount()
    var
        Assert: Codeunit "Library Assert";
        TestData: Codeunit "Whse Test Data ori";
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        Token: JsonToken;
    begin
        TestData.CreateBinContent('WH-PAGE', 'BIN-01', 'ITEM-02', '', 'PCS');
        TestData.CreateBinContent('WH-PAGE', 'BIN-02', 'ITEM-02', '', 'PCS');

        ExecuteBinContentGet('{"locationCode":"WH-PAGE","skip":1,"take":1}', ResponseJson);

        Assert.IsTrue(GetIntegerProperty(ResponseJson, 'noOfRecords') = 2, 'The count should include both matching rows.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The response should contain results.');
        ResultArray := Token.AsArray();
        Assert.IsTrue(ResultArray.Count() = 1, 'The requested page should contain one row.');
        Assert.IsTrue(ResultArray.Get(0, Token), 'The page entry should exist.');
        Assert.IsTrue(Token.AsObject().Get('binCode', Token), 'The page entry bin should be present.');
        Assert.IsTrue(Token.AsValue().AsText() = 'BIN-02', 'Skip should advance to the second row.');
    end;

    /// <summary>Verifies that a zero-match list query succeeds with an empty result.</summary>
    [Test]
    procedure GetWithNoMatchesReturnsEmptySuccess()
    var
        Assert: Codeunit "Library Assert";
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        Token: JsonToken;
    begin
        ExecuteBinContentGet('{"locationCode":"WH-NO-MATCH","itemNo":"MISSING"}', ResponseJson);

        Assert.IsTrue(GetTextProperty(ResponseJson, 'status') = 'Success', 'A zero-match list query should succeed.');
        Assert.IsTrue(GetIntegerProperty(ResponseJson, 'noOfRecords') = 0, 'The zero-match count should be zero.');
        Assert.IsTrue(ResponseJson.Get('result', Token), 'The response should contain a result array.');
        ResultArray := Token.AsArray();
        Assert.IsTrue(ResultArray.Count() = 0, 'The zero-match result array should be empty.');
    end;

    /// <summary>Verifies that IsEnabled is false when the caller cannot read Bin Content.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutReadPermission()
    var
        Assert: Codeunit "Library Assert";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');

        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.BinContent.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.BinContent.Get must be disabled without read permission on Bin Content.');
    end;

    local procedure ExecuteBinContentGet(RequestText: Text; var ResponseJson: JsonObject)
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[50];
        ResponseText: Text;
    begin
        RequestContent.AddText(RequestText);
        Dispatcher.Execute(
            Enum::"Message Type ori"::"Warehouse.BinContent.Get",
            Enum::"Message Version ori"::"1.0",
            '',
            'Warehouse Bin Content Get Tests',
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