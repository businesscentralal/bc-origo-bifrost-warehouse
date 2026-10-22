namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Completeness guard for the contract and discovery of every Warehouse message type, as Foundation does for its own
/// types: every chapter is declared, every error carries a machine code, the direction matches the effect and the
/// discovery texts exist in English and Icelandic. A type added later fails here until it is complete.
/// </summary>
codeunit 97031 "Whse Contract Parity Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ContractAssert: Codeunit "Whse Contract Assert ori";

    /// <summary>Every Warehouse type declares the envelope, target, response, errors, effect, related, overview, notes and examples chapters.</summary>
    [Test]
    procedure EveryType_DeclaresEveryRequiredChapter()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        TypeName: Text;
        TypeCount: Integer;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Clear(Contract);
            Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), TypeName + ' has a contract.');
            Assert.IsTrue(Contract.Contains('envelope'), TypeName + ' declares the envelope.');
            Assert.IsTrue(Contract.Contains('target'), TypeName + ' declares the target.');
            Assert.IsTrue(Contract.Contains('response'), TypeName + ' declares the response.');
            Assert.IsTrue(Contract.Contains('errors'), TypeName + ' declares the errors.');
            Assert.IsTrue(Contract.Contains('effect'), TypeName + ' declares the effect.');
            Assert.IsTrue(Contract.Contains('metering'), TypeName + ' has the metering chapter.');
            Assert.IsTrue(Contract.Contains('related'), TypeName + ' declares the related types.');
            Assert.AreNotEqual('', TextOf(Contract, 'overview'), TypeName + ' declares the overview.');
            Assert.AreNotEqual('', TextOf(Contract, 'notes'), TypeName + ' declares the notes.');
            Assert.IsTrue(ArrayOf(Contract, 'related').Count() > 0, TypeName + ' names at least one related type.');
            Assert.IsTrue(ArrayOf(Contract, 'examples').Count() > 0, TypeName + ' declares at least one example.');
            if NoParameterTypes().Contains(TypeName) then
                Assert.IsFalse(Contract.Contains('parameters'), TypeName + ' reads no data key, so it declares no parameters.')
            else
                Assert.IsTrue(ArrayOf(Contract, 'parameters').Count() > 0, TypeName + ' declares its parameters.');
            TypeCount += 1;
        end;
        Assert.IsTrue(TypeCount >= 42, 'Every Warehouse type is checked.');
    end;

    /// <summary>Every type that changes data, or previews a change, declares a workflow; only the plain reads may leave it out.</summary>
    [Test]
    procedure EveryChangingType_DeclaresAWorkflow()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Implementation: Interface "Msg Interface ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        Workflow: JsonObject;
        Steps: JsonArray;
        Step: JsonToken;
        Token: JsonToken;
        TypeName: Text;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Implementation := MessageType;
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            if Contract.Get('workflow', Token) then begin
                Workflow := Token.AsObject();
                Steps := ArrayOf(Workflow, 'steps');
                Assert.IsTrue(Steps.Count() > 0, TypeName + ' workflow has steps.');
                foreach Step in Steps do begin
                    Assert.AreNotEqual('', TextOf(Step.AsObject(), 'messageType'), TypeName + ' workflow step names a message type.');
                    Assert.AreNotEqual('', TextOf(Step.AsObject(), 'purpose'), TypeName + ' workflow step has a purpose.');
                end;
            end else
                Assert.IsTrue(Implementation.GetMessageDirection() = Enum::"Msg Direction ori"::Outbound, TypeName + ' changes or previews data, so it declares a workflow.');
        end;
    end;

    /// <summary>Every error entry carries a machine code that exists, the condition and what to do; an entry without a code carries the error text.</summary>
    [Test]
    procedure EveryErrorEntry_CarriesCodeConditionAndFix()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        Entry: JsonToken;
        ErrorCodes: List of [Text];
        TypeName: Text;
        EntryCode: Text;
        EntryCount: Integer;
    begin
        ErrorCodes := Enum::"Bifrost Error Code ori".Names();
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            Assert.IsTrue(ArrayOf(Contract, 'errors').Count() > 0, TypeName + ' lists its errors.');
            foreach Entry in ArrayOf(Contract, 'errors') do begin
                EntryCode := TextOf(Entry.AsObject(), 'code');
                if EntryCode = '' then
                    Assert.AreNotEqual('', TextOf(Entry.AsObject(), 'error'), TypeName + ' error entry without a code carries the error text.')
                else
                    Assert.IsTrue(ErrorCodes.Contains(EntryCode), TypeName + ' error code ' + EntryCode + ' exists.');
                Assert.AreNotEqual('', TextOf(Entry.AsObject(), 'when'), TypeName + ' error ' + EntryCode + ' states when it is answered.');
                Assert.AreNotEqual('', TextOf(Entry.AsObject(), 'fix'), TypeName + ' error ' + EntryCode + ' states what to do.');
                EntryCount += 1;
            end;
        end;
        Assert.IsTrue(EntryCount >= 42, 'Error entries were checked.');
    end;

    /// <summary>The direction matches the effect: changes are Inbound, plain reads are Outbound, and the preview types read through an Inbound request.</summary>
    [Test]
    procedure EveryType_DirectionMatchesEffect()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Implementation: Interface "Msg Interface ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        EffectObject: JsonObject;
        Token: JsonToken;
        TypeName: Text;
        EffectKind: Text;
        ExpectedDirection: Enum "Msg Direction ori";
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Implementation := MessageType;
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            Contract.Get('effect', Token);
            EffectObject := Token.AsObject();
            EffectKind := TextOf(EffectObject, 'effect');
            Assert.IsTrue(EffectKind in ['read', 'write', 'irreversible'], TypeName + ' effect is read, write or irreversible.');
            Assert.AreNotEqual('', TextOf(EffectObject, 'changes'), TypeName + ' effect states what changes.');
            Assert.AreNotEqual('', TextOf(EffectObject, 'permissionSet'), TypeName + ' effect names the permission set.');
            Assert.IsTrue(EffectObject.Contains('idempotent'), TypeName + ' effect states whether it is idempotent.');
            if (EffectKind = 'read') and not TypeName.EndsWith('PreviewPost') then
                ExpectedDirection := Enum::"Msg Direction ori"::Outbound
            else
                ExpectedDirection := Enum::"Msg Direction ori"::Inbound;
            Assert.IsTrue(Implementation.GetMessageDirection() = ExpectedDirection, TypeName + ' direction matches the ' + EffectKind + ' effect.');
        end;
    end;

    /// <summary>Every parameter is declared with a name, a JSON type and a description, and every array of objects lists its children.</summary>
    [Test]
    procedure EveryParameter_IsDescribed()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        Parameter: JsonToken;
        TypeName: Text;
        ParameterName: Text;
        ParameterCount: Integer;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            foreach Parameter in ArrayOf(Contract, 'parameters') do begin
                ParameterName := TextOf(Parameter.AsObject(), 'name');
                Assert.AreNotEqual('', ParameterName, TypeName + ' parameter has a name.');
                Assert.AreNotEqual('', TextOf(Parameter.AsObject(), 'type'), TypeName + ' parameter ' + ParameterName + ' has a type.');
                Assert.AreNotEqual('', TextOf(Parameter.AsObject(), 'description'), TypeName + ' parameter ' + ParameterName + ' has a description.');
                if TextOf(Parameter.AsObject(), 'type') = 'array' then
                    if not ScalarArrayParameters().Contains(TypeName + '|' + ParameterName) then
                        Assert.IsTrue(ArrayOf(Parameter.AsObject(), 'children').Count() > 0, TypeName + ' array parameter ' + ParameterName + ' lists its children.');
                ParameterCount += 1;
            end;
        end;
        Assert.IsTrue(ParameterCount >= 42, 'Parameters were checked.');
    end;

    /// <summary>Every response chapter lists fields with a name, a type and a description; every example is a real request and response object.</summary>
    [Test]
    procedure ResponseAndExamples_AreComplete()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        ResponseObject: JsonObject;
        Token: JsonToken;
        Field: JsonToken;
        Example: JsonToken;
        TypeName: Text;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            Contract.Get('response', Token);
            ResponseObject := Token.AsObject();
            Assert.IsTrue(ArrayOf(ResponseObject, 'fields').Count() > 0, TypeName + ' response lists fields.');
            foreach Field in ArrayOf(ResponseObject, 'fields') do begin
                Assert.AreNotEqual('', TextOf(Field.AsObject(), 'name'), TypeName + ' response field has a name.');
                Assert.AreNotEqual('', TextOf(Field.AsObject(), 'type'), TypeName + ' response field ' + TextOf(Field.AsObject(), 'name') + ' has a type.');
                Assert.AreNotEqual('', TextOf(Field.AsObject(), 'description'), TypeName + ' response field ' + TextOf(Field.AsObject(), 'name') + ' has a description.');
            end;
            foreach Example in ArrayOf(Contract, 'examples') do begin
                Assert.AreNotEqual('', TextOf(Example.AsObject(), 'title'), TypeName + ' example has a title.');
                Assert.IsTrue(Example.AsObject().Get('request', Token), TypeName + ' example has a request.');
                Assert.IsTrue(Token.IsObject(), TypeName + ' example request is a JSON object.');
                Assert.IsTrue(Example.AsObject().Get('response', Token), TypeName + ' example has a response.');
                Assert.IsTrue(Token.IsObject(), TypeName + ' example response is a JSON object.');
            end;
        end;
    end;

    /// <summary>Every related type, and every workflow step, names a message type that exists.</summary>
    [Test]
    procedure RelatedAndWorkflow_NameExistingTypes()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        Token: JsonToken;
        Entry: JsonToken;
        TypeNames: List of [Text];
        TypeName: Text;
    begin
        TypeNames := Enum::"Message Type ori".Names();
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            foreach Entry in ArrayOf(Contract, 'related') do begin
                Assert.IsTrue(TypeNames.Contains(TextOf(Entry.AsObject(), 'name')), TypeName + ' related type exists: ' + TextOf(Entry.AsObject(), 'name'));
                Assert.AreNotEqual('', TextOf(Entry.AsObject(), 'useInsteadWhen'), TypeName + ' related type says when to use it.');
            end;
            if Contract.Get('workflow', Token) then
                foreach Entry in ArrayOf(Token.AsObject(), 'steps') do
                    Assert.IsTrue(TypeNames.Contains(TextOf(Entry.AsObject(), 'messageType')), TypeName + ' workflow step type exists: ' + TextOf(Entry.AsObject(), 'messageType'));
        end;
    end;

    /// <summary>Every type has a description, a selection description and keywords in English and in Icelandic, and the Icelandic texts are translated.</summary>
    [Test]
    procedure EveryType_DiscoveryTextsExistInBothLanguages()
    var
        Implementation: Interface "Msg Interface ori";
        Discovery: Interface "Msg Discovery ori";
        MessageType: Enum "Message Type ori";
        OriginalLanguage: Integer;
        TypeName: Text;
        EnglishDescription: Text;
        EnglishSelection: Text;
        EnglishKeywords: Text;
        TypeCount: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Implementation := MessageType;
            Discovery := MessageType;
            GlobalLanguage(1033);
            EnglishDescription := Implementation.GetDescription();
            EnglishSelection := Discovery.GetSelectionDescription();
            EnglishKeywords := Discovery.GetKeywords();
            GlobalLanguage(1039);
            Assert.AreNotEqual('', EnglishDescription, TypeName + ' has a description.');
            Assert.AreNotEqual('', EnglishSelection, TypeName + ' has a selection description.');
            Assert.AreNotEqual('', EnglishKeywords, TypeName + ' has keywords.');
            Assert.AreNotEqual('', Implementation.GetDescription(), TypeName + ' has an Icelandic description.');
            Assert.AreNotEqual(EnglishDescription, Implementation.GetDescription(), TypeName + ' description is translated.');
            Assert.AreNotEqual(EnglishSelection, Discovery.GetSelectionDescription(), TypeName + ' selection description is translated.');
            Assert.AreNotEqual(EnglishKeywords, Discovery.GetKeywords(), TypeName + ' keywords are translated.');
            GlobalLanguage(OriginalLanguage);
            TypeCount += 1;
        end;
        GlobalLanguage(OriginalLanguage);
        Assert.IsTrue(TypeCount >= 42, 'Every Warehouse type is checked.');
    end;

    /// <summary>The notes and overview of every type name no AL object and no internal procedure.</summary>
    [Test]
    procedure NotesAndOverview_NameNoAlObjects()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        TypeName: Text;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            TypeName := ContractAssert.TypeName(MessageType);
            Clear(Contract);
            ContractMgt.GetContract(MessageType, Contract);
            ContractAssert.AssertNamesNoAlObject(TextOf(Contract, 'notes'), TypeName + ' notes');
            ContractAssert.AssertNamesNoAlObject(TextOf(Contract, 'overview'), TypeName + ' overview');
        end;
    end;

    local procedure NoParameterTypes() Names: List of [Text]
    begin
        Names.Add('Warehouse.Pick.Register');
        Names.Add('Warehouse.Putaway.Register');
        Names.Add('Warehouse.Shipment.Release');
        Names.Add('Warehouse.Shipment.Reopen');
    end;

    local procedure ScalarArrayParameters() Names: List of [Text]
    begin
        Names.Add('Warehouse.Receipt.GetSourceDocuments|sourceNos');
        Names.Add('Warehouse.Shipment.GetSourceDocuments|sourceNos');
    end;

    local procedure TextOf(Source: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure ArrayOf(Source: JsonObject; KeyName: Text) Result: JsonArray
    var
        Token: JsonToken;
    begin
        if not Source.Get(KeyName, Token) then
            exit;
        if Token.IsArray() then
            Result := Token.AsArray();
    end;
}
