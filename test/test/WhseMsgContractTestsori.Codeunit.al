namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Conformance tests for the Warehouse message type contracts.
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
        AssertContract("Message Type ori"::"Warehouse.Shipment.PreviewPost", 'read', true);
        AssertContract("Message Type ori"::"Warehouse.Receipt.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Receipt.Post", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Receipt.PreviewPost", 'read', true);
        AssertContract("Message Type ori"::"Warehouse.Pick.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Pick.Register", 'irreversible', false);
        AssertContract("Message Type ori"::"Warehouse.Putaway.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Putaway.Register", 'irreversible', false);
        AssertContract("Message Type ori"::"Warehouse.Bin.Get", 'read', true);
        AssertContract("Message Type ori"::"Warehouse.Bin.Create", 'write', true);
        AssertContract("Message Type ori"::"Warehouse.DefaultBin.Set", 'write', true);
        AssertContract("Message Type ori"::"Warehouse.Movement.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.Movement.Register", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.InventoryPick.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.InventoryPick.Post", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.InventoryPutAway.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.InventoryPutAway.Post", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.InventoryMovement.Create", 'irreversible', true);
        AssertContract("Message Type ori"::"Warehouse.InventoryMovement.Register", 'irreversible', true);
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
        AssertContract(MessageType, 'read', true);
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

    /// <summary>Issue #24 AC04: document targets preserve descriptions and declare each data key.</summary>
    [Test]
    procedure DocumentTargets_DeclareEachIdentifierKey()
    begin
        // Story #24, AC04 | Time: independent of Today/WorkDate | Risk: contract shape only.
        AssertDocumentTarget("Message Type ori"::"Warehouse.Shipment.Post", 'Warehouse Shipment Header', 'data.systemId, data.recordSystemId, data.id, data.shipmentNo, data.no');
        AssertDocumentTarget("Message Type ori"::"Warehouse.Shipment.PreviewPost", 'Warehouse Shipment Header', 'data.systemId, data.recordSystemId, data.id, data.shipmentNo, data.no');
        AssertDocumentTarget("Message Type ori"::"Warehouse.Receipt.Post", 'Warehouse Receipt Header', 'data.systemId, data.recordSystemId, data.id, data.receiptNo, data.no');
        AssertDocumentTarget("Message Type ori"::"Warehouse.Receipt.PreviewPost", 'Warehouse Receipt Header', 'data.systemId, data.recordSystemId, data.id, data.receiptNo, data.no');
        AssertDocumentTarget("Message Type ori"::"Warehouse.Pick.Create", 'Warehouse Shipment Header', 'data.systemId, data.recordSystemId, data.id, data.whseShipmentNo, data.shipmentNo, data.no');
        AssertDocumentTarget("Message Type ori"::"Warehouse.Putaway.Create", 'Posted Whse. Receipt Header', 'data.systemId, data.recordSystemId, data.id, data.postedWhseReceiptNo, data.receiptNo, data.no');
    end;

    local procedure AssertDocumentTarget(MessageType: Enum "Message Type ori"; RecordName: Text; DataKeys: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        ActualTarget: JsonArray;
        ExpectedTarget: JsonArray;
        Token: JsonToken;
        ActualText: Text;
        ExpectedText: Text;
    begin
        // [GIVEN] The public contract for the document type.
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), 'Contract must exist.');
        Assert.IsTrue(Contract.Get('target', Token), 'Target chapter must exist.');
        ActualTarget := Token.AsArray();
        // [WHEN] Comparing to the three original entries, with each data key prefixed.
        ExpectedTarget.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the ' + RecordName + '.'));
        ExpectedTarget.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the ' + RecordName + '.'));
        ExpectedTarget.Add(ContractMgt.TargetEntry(DataKeys, 'guid or document no.', 'The identifier keys accepted for the ' + RecordName + '. Every supplied identifier is tried; conflicting identifiers are refused.'));
        ActualTarget.WriteTo(ActualText);
        ExpectedTarget.WriteTo(ExpectedText);
        // [THEN] Key order, kinds and descriptions remain unchanged.
        Assert.AreEqual(ExpectedText, ActualText, MessageTypeName(MessageType) + ' target must match its accepted identifiers.');
    end;

    /// <summary>Issue #34 AC01: Activity.Get documents every identifier key it reads, including the aliases read since #37.</summary>
    [Test]
    procedure ActivityGet_TargetListsEveryKeyItReads()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Token: JsonToken;
        TargetText: Text;
    begin
        // Story #34, AC01 | Time: independent of Today/WorkDate | Risk: register aliases must remain.
        Assert.IsTrue(ContractMgt.GetContract("Message Type ori"::"Warehouse.Activity.Get", Contract), 'Contract exists.');
        Contract.Get('target', Token);
        Token.WriteTo(TargetText);
        Assert.IsTrue(TargetText.Contains('data.systemId'), 'systemId is supported.');
        Assert.IsTrue(TargetText.Contains('data.no'), 'no is supported.');
        Assert.IsTrue(TargetText.Contains('recordSystemId'), 'recordSystemId remains supported after #37/#38.');
        Assert.IsTrue(TargetText.Contains('data.id'), 'id remains supported after #37/#38.');
        Assert.IsTrue(TargetText.Contains('activityNo'), 'activityNo remains supported after #37/#38.');
    end;

    /// <summary>Issues #21 and #34: optional Activity.Get has strict-format and supported conflict errors.</summary>
    [Test]
    procedure ActivityGet_ErrorsDoNotListUnanswerableCodes()
    begin
        // Story #34, AC02 | Time: independent of Today/WorkDate | Risk: retains #37/#38 conflicts; a missing identifier still allows collection reads.
        AssertErrorCount("Message Type ori"::"Warehouse.Activity.Get", 'MissingParameter', 0);
        AssertErrorCount("Message Type ori"::"Warehouse.Activity.Get", 'ConflictingIdentifiers', 1);
        AssertErrorCount("Message Type ori"::"Warehouse.Activity.Get", 'RecordNotFound', 1);
        AssertErrorCount("Message Type ori"::"Warehouse.Activity.Get", 'InvalidParameterFormat', 1);
        AssertErrorCount("Message Type ori"::"Warehouse.Activity.Get", 'InvalidParameter', 1);
        AssertErrorCount("Message Type ori"::"Warehouse.Activity.Get", 'MultipleErrors', 1);
    end;

    /// <summary>Issue #34 AC03: tableView is an optional string parameter.</summary>
    [Test]
    procedure BinContentGet_DeclaresTableView()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Parameter: JsonObject;
        Token: JsonToken;
        Parameters: JsonArray;
        Entry: JsonToken;
        Found: Boolean;
    begin
        // Story #34, AC03 | Time: independent of Today/WorkDate | Risk: declaration of existing behavior.
        Assert.IsTrue(ContractMgt.GetContract("Message Type ori"::"Warehouse.BinContent.Get", Contract), 'Contract exists.');
        Contract.Get('parameters', Token);
        Parameters := Token.AsArray();
        Found := false;
        foreach Entry in Parameters do begin
            Parameter := Entry.AsObject();
            Parameter.Get('name', Token);
            if Token.AsValue().AsText() = 'tableView' then begin
                Parameter.Get('type', Token);
                Assert.AreEqual('string', Token.AsValue().AsText(), 'tableView must be a string.');
                Parameter.Get('required', Token);
                Assert.IsFalse(Token.AsValue().AsBoolean(), 'tableView must be optional.');
                Found := true;
            end;
        end;
        Assert.IsTrue(Found, 'tableView must be declared.');
    end;

    /// <summary>Issue #34 AC04: register types retain their supported aliases.</summary>
    [Test]
    procedure ActivityRegister_TargetStillListsAliases()
    begin
        // Story #34, AC04 | Time: independent of Today/WorkDate | Risk: none.
        AssertRegisterAliases("Message Type ori"::"Warehouse.Pick.Register");
        AssertRegisterAliases("Message Type ori"::"Warehouse.Putaway.Register");
    end;

    /// <summary>Issue #21 AC6: each required lookup lists exactly one aggregation code.</summary>
    [Test]
    procedure LookupTypes_ErrorsChapter_ListsInvalidFormatAndMultipleErrors()
    var
        Types: List of [Enum "Message Type ori"];
        MessageType: Enum "Message Type ori";
    begin
        // Story #21, AC06 | Time: independent of Today/WorkDate | Risk: #34 tests optional Activity.Get separately.
        Types.Add("Message Type ori"::"Warehouse.Shipment.Post");
        Types.Add("Message Type ori"::"Warehouse.Shipment.PreviewPost");
        Types.Add("Message Type ori"::"Warehouse.Receipt.Post");
        Types.Add("Message Type ori"::"Warehouse.Receipt.PreviewPost");
        Types.Add("Message Type ori"::"Warehouse.Pick.Create");
        Types.Add("Message Type ori"::"Warehouse.Pick.Register");
        Types.Add("Message Type ori"::"Warehouse.Putaway.Create");
        Types.Add("Message Type ori"::"Warehouse.Putaway.Register");
        foreach MessageType in Types do begin
            AssertErrorCount(MessageType, 'InvalidParameterFormat', 1);
            AssertErrorCount(MessageType, 'MultipleErrors', 1);
            AssertErrorCount(MessageType, 'MissingParameter', 1);
            AssertErrorCount(MessageType, 'RecordNotFound', 1);
            AssertErrorCount(MessageType, 'ConflictingIdentifiers', 1);
        end;
    end;

    /// <summary>Issue #21 AC7: non-lookup types do not promise identifier aggregation.</summary>
    [Test]
    procedure NonLookupTypes_ErrorsChapter_HasNoMultipleErrors()
    begin
        // Story #21, AC07 | Time: independent of Today/WorkDate | Risk: none.
        AssertErrorCount("Message Type ori"::"Warehouse.BinContent.Get", 'MultipleErrors', 0);
        AssertErrorCount("Message Type ori"::"Warehouse.Shipment.Create", 'MultipleErrors', 0);
        AssertErrorCount("Message Type ori"::"Warehouse.Receipt.Create", 'MultipleErrors', 0);
        AssertErrorCount("Message Type ori"::"Warehouse.BinContent.Get", 'InvalidParameterFormat', 1);
    end;

    local procedure AssertRegisterAliases(MessageType: Enum "Message Type ori")
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Token: JsonToken;
        TargetText: Text;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), 'Contract exists.');
        Contract.Get('target', Token);
        Token.WriteTo(TargetText);
        Assert.IsTrue(TargetText.Contains('data.recordSystemId'), 'recordSystemId must remain.');
        Assert.IsTrue(TargetText.Contains('data.id'), 'id must remain.');
    end;

    local procedure AssertErrorCount(MessageType: Enum "Message Type ori"; CodeName: Text; ExpectedCount: Integer)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Errors: JsonArray;
        Entry: JsonToken;
        Token: JsonToken;
        Count: Integer;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), 'Contract exists.');
        Contract.Get('errors', Token);
        Errors := Token.AsArray();
        Count := 0;
        foreach Entry in Errors do
            if Entry.AsObject().Get('code', Token) then
                if Token.AsValue().AsText() = CodeName then
                    Count += 1;
        Assert.AreEqual(ExpectedCount, Count, MessageTypeName(MessageType) + ' ' + CodeName + ' count.');
    end;

    local procedure MessageTypeName(MessageType: Enum "Message Type ori"): Text
    begin
        exit(Enum::"Message Type ori".Names().Get(Enum::"Message Type ori".Ordinals().IndexOf(MessageType.AsInteger())));
    end;
}
