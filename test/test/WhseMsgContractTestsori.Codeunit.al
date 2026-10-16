namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Conformance tests for the twelve Warehouse message type contracts.
/// </summary>
codeunit 97027 "Whse Msg Contract Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure EveryWarehouseType_HasContractAndDiscovery()
    begin
        AssertContract("Message Type ori"::"Warehouse.BinContent.Get", 'read', true);
        AssertContract("Message Type ori"::"Warehouse.Activity.Get", 'read', true);
        AssertContract("Message Type ori"::"Warehouse.Shipment.Create", 'write', true);
        AssertContract("Message Type ori"::"Warehouse.Shipment.Post", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Shipment.PreviewPost", 'read', false);
        AssertContract("Message Type ori"::"Warehouse.Receipt.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Receipt.Post", 'irreversible', false);
        AssertContract("Message Type ori"::"Warehouse.Receipt.PreviewPost", 'read', false);
        AssertContract("Message Type ori"::"Warehouse.Pick.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Pick.Register", 'irreversible', false);
        AssertContract("Message Type ori"::"Warehouse.Putaway.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Putaway.Register", 'irreversible', false);
    end;

    /// <summary>
    /// Keeps the public receipt preview identity stable while enforcing its three-part name.
    /// </summary>
    [Test]
    procedure Scenario_AC01_ReceiptPreview_PreservesOrdinalAndCanonicalName()
    var
        MessageType: Enum "Message Type ori";
    begin
        // Story #40, AC01 | Time: independent of Today/WorkDate | Risk: public enum compatibility.
        // [GIVEN] The persisted receipt preview enum ordinal.
        MessageType := Enum::"Message Type ori".FromInteger(10078401);

        // [WHEN] Resolving that ordinal through the public enum name list.
        // [THEN] Existing stored values select the renamed contract and discovery implementation.
        Assert.AreEqual('Warehouse.Receipt.PreviewPost', MessageTypeName(MessageType), 'Receipt preview canonical name');
        Assert.AreEqual(10078401, Enum::"Message Type ori"::"Warehouse.Receipt.PreviewPost".AsInteger(), 'Receipt preview ordinal must not change');
        AssertContract(MessageType, 'read', false);
    end;

    /// <summary>
    /// Ensures bilingual receipt help and inbound workflows link to the renamed preview type.
    /// </summary>
    [Test]
    procedure Scenario_AC02_ReceiptHelp_UsesCanonicalPreviewNameInBothLanguages()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Discovery: Interface "Msg Discovery ori";
        Contract: JsonObject;
        Token: JsonToken;
        ContractText: Text;
        OriginalLanguage: Integer;
        LanguageId: Integer;
        Languages: List of [Integer];
    begin
        // Story #40, AC02 | Time: independent of Today/WorkDate | Risk: bilingual public help links.
        // [GIVEN] Both supported language contexts and the receipt posting contract.
        OriginalLanguage := GlobalLanguage();
        Languages.Add(1033);
        Languages.Add(1039);
        foreach LanguageId in Languages do begin
            GlobalLanguage(LanguageId);
            Discovery := Enum::"Message Type ori"::"Warehouse.Receipt.Post";

            // [WHEN] Reading the selection description, related types and shared inbound workflow.
            Assert.IsTrue(ContractMgt.GetContract(Enum::"Message Type ori"::"Warehouse.Receipt.Post", Contract), 'Receipt posting contract');
            Assert.IsTrue(Contract.Get('related', Token), 'Receipt posting related types');
            Token.WriteTo(ContractText);
            Assert.IsTrue(ContractText.Contains('Warehouse.Receipt.PreviewPost'), 'Related types must use the canonical preview name');
            Assert.IsTrue(Contract.Get('workflow', Token), 'Receipt posting workflow');
            Token.WriteTo(ContractText);

            // [THEN] Callers see a resolvable preview name in each public help surface.
            Assert.IsTrue(ContractText.Contains('Warehouse.Receipt.PreviewPost'), 'Workflow must use the canonical preview name');
            Assert.IsTrue(Discovery.GetSelectionDescription().Contains('Warehouse.Receipt.PreviewPost'), 'Selection description must use the canonical preview name');
            Clear(Contract);
        end;
        GlobalLanguage(OriginalLanguage);
    end;

    local procedure AssertContract(MessageType: Enum "Message Type ori"; ExpectedEffect: Text; HasParameters: Boolean)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Discovery: Interface "Msg Discovery ori";
        Contract: JsonObject;
        Token: JsonToken;
        Description: Text;
        Keywords: Text;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), MessageTypeName(MessageType) + ' has contract');
        Assert.IsTrue(Contract.Contains('envelope'), MessageTypeName(MessageType) + ' envelope');
        Assert.IsTrue(Contract.Contains('target'), MessageTypeName(MessageType) + ' target');
        Assert.IsTrue(Contract.Contains('response'), MessageTypeName(MessageType) + ' response');
        Assert.IsTrue(Contract.Contains('errors'), MessageTypeName(MessageType) + ' errors');
        Assert.IsTrue(Contract.Contains('effect'), MessageTypeName(MessageType) + ' effect');
        Assert.IsTrue(Contract.Contains('metering'), MessageTypeName(MessageType) + ' metering');
        Assert.IsTrue(Contract.Contains('related'), MessageTypeName(MessageType) + ' related');
        Assert.AreEqual(HasParameters, Contract.Contains('parameters'), MessageTypeName(MessageType) + ' parameters');
        Assert.IsTrue(Contract.Get('effect', Token), MessageTypeName(MessageType) + ' effect object');
        Assert.IsTrue(Token.AsObject().Get('effect', Token), MessageTypeName(MessageType) + ' effect value');
        Assert.AreEqual(ExpectedEffect, Token.AsValue().AsText(), MessageTypeName(MessageType) + ' effect kind');

        Discovery := MessageType;
        Description := Discovery.GetSelectionDescription();
        Keywords := Discovery.GetKeywords();
        Assert.IsTrue(Description <> '', MessageTypeName(MessageType) + ' selection description');
        Assert.IsTrue(Keywords <> '', MessageTypeName(MessageType) + ' keywords');
    end;

    [Test]
    procedure ActivityContractDescribesHeadersAndLines()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Response: JsonObject;
        Field: JsonObject;
        Child: JsonObject;
        Token: JsonToken;
        Fields: JsonArray;
        Children: JsonArray;
        Index: Integer;
        FieldName: Text;
        HasHeaderField: Boolean;
        HasLines: Boolean;
    begin
        Assert.IsTrue(ContractMgt.GetContract("Message Type ori"::"Warehouse.Activity.Get", Contract), 'Activity contract should exist');
        Assert.IsTrue(Contract.Get('response', Token), 'Activity contract should have a response');
        Response := Token.AsObject();
        Assert.IsTrue(Response.Get('fields', Token), 'Activity response should have fields');
        Fields := Token.AsArray();

        for Index := 0 to Fields.Count() - 1 do begin
            Fields.Get(Index, Token);
            Field := Token.AsObject();
            if not Field.Get('name', Token) then
                continue;
            FieldName := Token.AsValue().AsText();
            if FieldName <> 'result' then
                continue;
            Assert.IsTrue(Field.Get('children', Token), 'Activity result should describe its children');
            Children := Token.AsArray();
            for Index := 0 to Children.Count() - 1 do begin
                Children.Get(Index, Token);
                Child := Token.AsObject();
                if not Child.Get('name', Token) then
                    continue;
                FieldName := Token.AsValue().AsText();
                HasHeaderField := HasHeaderField or (FieldName = 'no');
                HasLines := HasLines or (FieldName = 'lines');
            end;
            break;
        end;

        Assert.IsTrue(HasHeaderField, 'Activity result should describe activity header fields');
        Assert.IsTrue(HasLines, 'Activity result should describe its nested lines array');
    end;

    local procedure MessageTypeName(MessageType: Enum "Message Type ori"): Text
    begin
        exit(Enum::"Message Type ori".Names().Get(Enum::"Message Type ori".Ordinals().IndexOf(MessageType.AsInteger())));
    end;
}
