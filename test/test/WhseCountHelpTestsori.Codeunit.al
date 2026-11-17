namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// #97: irreversible warehouse types keep that effect and name what expectedCount counts, in en-US and is-IS.
/// #99: commit-only create and calculate types declare write instead.
/// </summary>
codeunit 97092 "Whse Count Help Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";

    /// <summary>Every listed irreversible type names its unit once, in English and Icelandic, and stays irreversible.</summary>
    [Test]
    procedure IrreversibleTypes_NameTheCountInBothLanguages()
    var
        MessageType: Enum "Message Type ori";
        OriginalLanguage: Integer;
    begin
        // #97 AC01-AC03 | Time: independent of WorkDate | Risk: session language restored after the check.
        OriginalLanguage := GlobalLanguage();
        foreach MessageType in IrreversibleTypes() do begin
            AssertEnglishContract(MessageType);
            AssertIcelandicLabel(MessageType);
        end;
        GlobalLanguage(OriginalLanguage);
    end;

    /// <summary>A second contract read does not repeat the count sentence.</summary>
    [Test]
    procedure CountSentence_IsNotRepeated()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        FirstContract: JsonObject;
        SecondContract: JsonObject;
        FirstChanges: Text;
        SecondChanges: Text;
    begin
        // #97 AC02 | Time: independent of WorkDate | Risk: none.
        Assert.IsTrue(ContractMgt.GetContract("Message Type ori"::"Warehouse.Shipment.Post", FirstContract), 'First contract.');
        Assert.IsTrue(ContractMgt.GetContract("Message Type ori"::"Warehouse.Shipment.Post", SecondContract), 'Second contract.');
        FirstChanges := EffectChanges(FirstContract);
        SecondChanges := EffectChanges(SecondContract);
        Assert.AreEqual(FirstChanges, SecondChanges, 'The count sentence is stable.');
        Assert.AreEqual(1, OccurrenceCount(FirstChanges, 'expectedCount counts '), 'The unit is named once.');
    end;

    /// <summary>A reversible write does not gain the irreversible count sentence or the confirmation parameter.</summary>
    [Test]
    procedure ReversibleWrite_DoesNotNameACount()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Changes: Text;
    begin
        // #97 AC01 | Time: independent of WorkDate | Risk: none.
        Assert.IsTrue(ContractMgt.GetContract("Message Type ori"::"Warehouse.Journal.Create", Contract), 'Journal create contract.');
        Assert.AreEqual('write', EffectKind(Contract), 'Journal create stays a write.');
        Changes := EffectChanges(Contract);
        Assert.AreEqual(0, OccurrenceCount(Changes, 'expectedCount counts '), 'A write does not name expectedCount.');
        Assert.IsFalse(HasParameter(Contract, 'expectedCount'), 'A write does not declare expectedCount.');
    end;

    /// <summary>Missing, matching and wrong counts, and a write that does not ask for confirmation.</summary>
    [Test]
    procedure Confirmation_FollowsTheRealEffect()
    var
        Missing: JsonObject;
        Matching: JsonObject;
        Wrong: JsonObject;
        WriteResponse: JsonObject;
        Expected: Integer;
    begin
        // #97 AC03 | Time: independent of WorkDate | Risk: a missing pick is not created.
        Assert.IsTrue(Send("Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-97', '{}', Missing), 'Missing count returns JSON.');
        Assert.AreEqual('ConfirmationRequired', ResponseCode(Missing), 'An irreversible call without expectedCount is a preview.');
        Expected := ResponseInteger(Missing, 'expected');
        Assert.AreEqual(1, Expected, 'The preview count is one call.');

        Assert.IsTrue(Send("Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-97', '{"expectedCount":1}', Matching), 'Matching count returns JSON.');
        Assert.AreNotEqual('ConfirmationRequired', ResponseCode(Matching), 'A matching count is accepted.');
        Assert.AreNotEqual('ConfirmationMismatch', ResponseCode(Matching), 'A matching count is not a mismatch.');

        Assert.IsTrue(Send("Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-97', '{"expectedCount":2}', Wrong), 'Wrong count returns JSON.');
        Assert.AreEqual('ConfirmationMismatch', ResponseCode(Wrong), 'A count other than one is refused.');

        Assert.IsTrue(Send("Message Type ori"::"Warehouse.Journal.Create", '', '{}', WriteResponse), 'Write call returns JSON.');
        Assert.AreNotEqual('ConfirmationRequired', ResponseCode(WriteResponse), 'A write does not require expectedCount.');
    end;

    /// <summary>#99 AC01: commit-only create and calculate types declare write and no longer name or declare expectedCount.</summary>
    [Test]
    procedure CommitOnlyTypes_DeclareWriteWithoutExpectedCount()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        TypeName: Text;
    begin
        // #99 AC01 | Time: independent of WorkDate | Risk: none.
        GlobalLanguage(1033);
        foreach MessageType in WriteTypes() do begin
            TypeName := TypeNameOf(MessageType);
            Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), TypeName + ' contract.');
            Assert.AreEqual('write', EffectKind(Contract), TypeName + ' declares write.');
            Assert.AreEqual(0, OccurrenceCount(EffectChanges(Contract), 'expectedCount'), TypeName + ' effect names no count.');
            Assert.IsFalse(HasParameter(Contract, 'expectedCount'), TypeName + ' declares no expectedCount.');
        end;
    end;

    /// <summary>#99 AC02: each write type runs without expectedCount while confirmation of irreversible messages is on.</summary>
    [Test]
    procedure CommitOnlyTypes_RunWithoutExpectedCount()
    var
        MessageType: Enum "Message Type ori";
        ResponseJson: JsonObject;
    begin
        // #99 AC02 | Time: independent of WorkDate | Risk: an empty request creates nothing and returns its own refusal.
        foreach MessageType in WriteTypes() do begin
            Assert.IsTrue(Send(MessageType, '', '{}', ResponseJson), TypeNameOf(MessageType) + ' returns JSON.');
            Assert.AreNotEqual('ConfirmationRequired', ResponseCode(ResponseJson), TypeNameOf(MessageType) + ' does not ask for expectedCount.');
        end;
    end;

    /// <summary>#99 AC03: postings and registrations stay irreversible, and the types that remain irreversible are not changed.</summary>
    [Test]
    procedure PostingTypes_StayIrreversible()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
    begin
        // #99 AC03 | Time: independent of WorkDate | Risk: none.
        foreach MessageType in IrreversibleTypes() do begin
            Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), TypeNameOf(MessageType) + ' contract.');
            Assert.AreEqual('irreversible', EffectKind(Contract), TypeNameOf(MessageType) + ' stays irreversible.');
            Assert.IsTrue(HasParameter(Contract, 'expectedCount'), TypeNameOf(MessageType) + ' still declares expectedCount.');
        end;
    end;

    local procedure WriteTypes() Types: List of [Enum "Message Type ori"]
    begin
        Types.Add("Message Type ori"::"Warehouse.Receipt.Create");
        Types.Add("Message Type ori"::"Warehouse.Pick.Create");
        Types.Add("Message Type ori"::"Warehouse.Putaway.Create");
        Types.Add("Message Type ori"::"Warehouse.Movement.Create");
        Types.Add("Message Type ori"::"Warehouse.InventoryPick.Create");
        Types.Add("Message Type ori"::"Warehouse.InventoryPutAway.Create");
        Types.Add("Message Type ori"::"Warehouse.InventoryMovement.Create");
        Types.Add("Message Type ori"::"Warehouse.BinReplenishment.Calculate");
        Types.Add("Message Type ori"::"Warehouse.Worksheet.CreateActivities");
    end;

    local procedure AssertEnglishContract(MessageType: Enum "Message Type ori")
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Contract: JsonObject;
        Changes: Text;
        Description: Text;
        Sentence: Text;
        TypeName: Text;
    begin
        // Foundation builds contract chapters in English (#777), so the published help is checked at 1033.
        TypeName := TypeNameOf(MessageType);
        GlobalLanguage(1033);
        Sentence := Parts.CountDefinition(MessageType);
        Assert.IsTrue(Sentence.StartsWith('expectedCount counts '), TypeName + ' English sentence names the unit.');
        Assert.IsTrue(Sentence.Contains(DistinctUnit(MessageType, 1033)), TypeName + ' English sentence names its own unit.');
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), TypeName + ' contract.');
        Assert.AreEqual('irreversible', EffectKind(Contract), TypeName + ' stays irreversible.');
        Changes := EffectChanges(Contract);
        Assert.IsTrue(Changes.StartsWith(Sentence), TypeName + ' effect.changes starts with the English count sentence.');
        Assert.AreEqual(1, OccurrenceCount(Changes, 'expectedCount counts '), TypeName + ' names the unit once.');
        Description := ParameterDescription(Contract, 'expectedCount');
        Assert.IsTrue(Description.StartsWith(Sentence), TypeName + ' expectedCount starts with the English count sentence.');
        Assert.IsTrue(Description.Contains('read expected'), TypeName + ' expectedCount says to read expected.');
        Assert.IsTrue(Description.Contains('without expectedCount'), TypeName + ' expectedCount names the preview call.');
        Assert.IsFalse(ParameterRequired(Contract, 'expectedCount'), TypeName + ' expectedCount stays optional.');
    end;

    local procedure AssertIcelandicLabel(MessageType: Enum "Message Type ori")
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Sentence: Text;
        Description: Text;
        TypeName: Text;
    begin
        // The is-IS label is what the XLF carries. GetContract does not publish it: chapters stay English.
        TypeName := TypeNameOf(MessageType);
        GlobalLanguage(1039);
        Sentence := Parts.CountDefinition(MessageType);
        Description := Parts.ExpectedCountParameterDescription(MessageType);
        Assert.IsTrue(Sentence.StartsWith('expectedCount telur '), TypeName + ' Icelandic sentence names the unit.');
        Assert.IsTrue(Sentence.Contains(DistinctUnit(MessageType, 1039)), TypeName + ' Icelandic sentence names its own unit.');
        Assert.IsTrue(Description.StartsWith(Sentence), TypeName + ' Icelandic parameter text starts with the count sentence.');
        Assert.IsTrue(Description.Contains('lesa expected'), TypeName + ' Icelandic parameter text says to read expected.');
        Assert.IsTrue(Description.Contains('án expectedCount'), TypeName + ' Icelandic parameter text names the preview call.');
    end;

    local procedure TypeNameOf(MessageType: Enum "Message Type ori"): Text
    begin
        exit(MessageType.Names().Get(MessageType.Ordinals().IndexOf(MessageType.AsInteger())));
    end;

    local procedure DistinctUnit(MessageType: Enum "Message Type ori"; LanguageId: Integer): Text
    begin
        if LanguageId = 1039 then
            case MessageType of
                "Message Type ori"::"Warehouse.Shipment.Post":
                    exit('vöruhúsaafhendingu');
                "Message Type ori"::"Warehouse.Receipt.Create":
                    exit('vöruhúsamóttökurnar');
                "Message Type ori"::"Warehouse.Receipt.Post":
                    exit('vöruhúsamóttöku');
                "Message Type ori"::"Warehouse.Pick.Create":
                    exit('vöruhúsatínslurnar');
                "Message Type ori"::"Warehouse.Pick.Register":
                    exit('vöruhúsatínslu');
                "Message Type ori"::"Warehouse.Putaway.Create":
                    exit('vöruhúsafrágangana');
                "Message Type ori"::"Warehouse.Putaway.Register":
                    exit('vöruhúsafrágang');
                "Message Type ori"::"Warehouse.Movement.Create":
                    exit('vöruhúsafærslurnar');
                "Message Type ori"::"Warehouse.Movement.Register":
                    exit('vöruhúsafærslu');
                "Message Type ori"::"Warehouse.InventoryPick.Create":
                    exit('birgðatínslurnar');
                "Message Type ori"::"Warehouse.InventoryPick.Post":
                    exit('birgðatínslu');
                "Message Type ori"::"Warehouse.InventoryPutAway.Create":
                    exit('birgðafrágangana');
                "Message Type ori"::"Warehouse.InventoryPutAway.Post":
                    exit('birgðafrágang');
                "Message Type ori"::"Warehouse.InventoryMovement.Create":
                    exit('birgðafærslurnar');
                "Message Type ori"::"Warehouse.InventoryMovement.Register":
                    exit('birgðafærslu');
                "Message Type ori"::"Warehouse.BinReplenishment.Calculate":
                    exit('færsluvinnublaðsins');
                "Message Type ori"::"Warehouse.Journal.Register":
                    exit('vöruhúsfærslubókarinnar');
                "Message Type ori"::"Warehouse.PhysInventory.Register":
                    exit('birgðatalningarfærslubókarinnar');
                "Message Type ori"::"Warehouse.Worksheet.CreateActivities":
                    exit('vinnublaðsins');
            end;
        case MessageType of
            "Message Type ori"::"Warehouse.Shipment.Post":
                exit('warehouse shipment');
            "Message Type ori"::"Warehouse.Receipt.Create":
                exit('warehouse receipts created');
            "Message Type ori"::"Warehouse.Receipt.Post":
                exit('warehouse receipt');
            "Message Type ori"::"Warehouse.Pick.Create":
                exit('warehouse picks created');
            "Message Type ori"::"Warehouse.Pick.Register":
                exit('warehouse pick');
            "Message Type ori"::"Warehouse.Putaway.Create":
                exit('warehouse put-aways created');
            "Message Type ori"::"Warehouse.Putaway.Register":
                exit('warehouse put-away');
            "Message Type ori"::"Warehouse.Movement.Create":
                exit('warehouse movements created');
            "Message Type ori"::"Warehouse.Movement.Register":
                exit('warehouse movement');
            "Message Type ori"::"Warehouse.InventoryPick.Create":
                exit('inventory picks created');
            "Message Type ori"::"Warehouse.InventoryPick.Post":
                exit('inventory pick');
            "Message Type ori"::"Warehouse.InventoryPutAway.Create":
                exit('inventory put-aways created');
            "Message Type ori"::"Warehouse.InventoryPutAway.Post":
                exit('inventory put-away');
            "Message Type ori"::"Warehouse.InventoryMovement.Create":
                exit('inventory movements created');
            "Message Type ori"::"Warehouse.InventoryMovement.Register":
                exit('inventory movement');
            "Message Type ori"::"Warehouse.BinReplenishment.Calculate":
                exit('movement worksheet lines');
            "Message Type ori"::"Warehouse.Journal.Register":
                exit('warehouse journal lines');
            "Message Type ori"::"Warehouse.PhysInventory.Register":
                exit('physical inventory journal lines');
            "Message Type ori"::"Warehouse.Worksheet.CreateActivities":
                exit('worksheet lines');
            else
                exit('missing unit');
        end;
    end;

    local procedure IrreversibleTypes() Types: List of [Enum "Message Type ori"]
    begin
        Types.Add("Message Type ori"::"Warehouse.Shipment.Post");
        Types.Add("Message Type ori"::"Warehouse.Receipt.Post");
        Types.Add("Message Type ori"::"Warehouse.Pick.Register");
        Types.Add("Message Type ori"::"Warehouse.Putaway.Register");
        Types.Add("Message Type ori"::"Warehouse.Movement.Register");
        Types.Add("Message Type ori"::"Warehouse.InventoryPick.Post");
        Types.Add("Message Type ori"::"Warehouse.InventoryPutAway.Post");
        Types.Add("Message Type ori"::"Warehouse.InventoryMovement.Register");
        Types.Add("Message Type ori"::"Warehouse.Journal.Register");
        Types.Add("Message Type ori"::"Warehouse.PhysInventory.Register");
    end;

    local procedure Send(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseText: Text;
        SubjectText: Text[250];
    begin
        Clear(ResponseJson);
        SubjectText := CopyStr(Subject, 1, MaxStrLen(SubjectText));
        if RequestText <> '' then
            RequestContent.AddText(RequestText);
        Dispatcher.Execute(MessageType, Enum::"Message Version ori"::"1.0", SubjectText,
            'Bifrost Warehouse Tests', 'text/json', RequestContent, ResponseContent, ResponseContentType, false);
        if ResponseContent.Length() = 0 then
            exit(false);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        exit(ResponseJson.ReadFrom(ResponseText));
    end;

    local procedure EffectKind(Contract: JsonObject): Text
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Contract.Get('effect', Token), 'Effect chapter.');
        exit(TextValue(Token.AsObject(), 'effect'));
    end;

    local procedure EffectChanges(Contract: JsonObject): Text
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Contract.Get('effect', Token), 'Effect chapter.');
        exit(TextValue(Token.AsObject(), 'changes'));
    end;

    local procedure ParameterDescription(Contract: JsonObject; ParameterName: Text): Text
    var
        Token: JsonToken;
        Parameter: JsonToken;
        NameToken: JsonToken;
    begin
        Assert.IsTrue(Contract.Get('parameters', Token), 'Parameters chapter.');
        foreach Parameter in Token.AsArray() do
            if Parameter.AsObject().Get('name', NameToken) then
                if NameToken.AsValue().AsText() = ParameterName then
                    exit(TextValue(Parameter.AsObject(), 'description'));
        exit('');
    end;

    local procedure ParameterRequired(Contract: JsonObject; ParameterName: Text): Boolean
    var
        Token: JsonToken;
        Parameter: JsonToken;
        NameToken: JsonToken;
        Required: JsonToken;
    begin
        Contract.Get('parameters', Token);
        foreach Parameter in Token.AsArray() do
            if Parameter.AsObject().Get('name', NameToken) then
                if NameToken.AsValue().AsText() = ParameterName then
                    if Parameter.AsObject().Get('required', Required) then
                        exit(Required.AsValue().AsBoolean());
        exit(true);
    end;

    local procedure HasParameter(Contract: JsonObject; ParameterName: Text): Boolean
    var
        Token: JsonToken;
        Parameter: JsonToken;
        NameToken: JsonToken;
    begin
        if not Contract.Get('parameters', Token) then
            exit(false);
        foreach Parameter in Token.AsArray() do
            if Parameter.AsObject().Get('name', NameToken) then
                if NameToken.AsValue().AsText() = ParameterName then
                    exit(true);
        exit(false);
    end;

    local procedure ResponseCode(ResponseJson: JsonObject): Text
    begin
        exit(TextValue(ResponseJson, 'code'));
    end;

    local procedure ResponseInteger(ResponseJson: JsonObject; PropertyName: Text): Integer
    var
        Token: JsonToken;
        Value: Integer;
    begin
        Assert.IsTrue(ResponseJson.Get(PropertyName, Token), PropertyName + ' is present.');
        Assert.IsTrue(Evaluate(Value, Token.AsValue().AsText()), PropertyName + ' is an integer.');
        exit(Value);
    end;

    local procedure TextValue(Source: JsonObject; PropertyName: Text): Text
    var
        Token: JsonToken;
    begin
        if Source.Get(PropertyName, Token) then
            if Token.IsValue() then
                exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure OccurrenceCount(Source: Text; Fragment: Text): Integer
    var
        Remaining: Text;
        Counted: Integer;
        Position: Integer;
    begin
        Remaining := Source;
        Position := StrPos(Remaining, Fragment);
        while Position > 0 do begin
            Counted += 1;
            Remaining := CopyStr(Remaining, Position + StrLen(Fragment));
            Position := StrPos(Remaining, Fragment);
        end;
        exit(Counted);
    end;
}
