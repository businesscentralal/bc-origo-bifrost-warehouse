namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Foundation.Company;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Document;
using System.Globalization;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Contract and help of the document flow types (#51, #52, #53, #54, #58) in en-US and is-IS.
/// </summary>
codeunit 97047 "Whse DocFlow Help Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";

    /// <summary>AC09/AC11: every new type has a full contract and its help in both languages, without AL object names.</summary>
    [Test]
    procedure NewTypes_HaveContractAndBilingualHelp()
    begin
        // Stories #51-#53, #58 help ACs | Time: independent of WorkDate | Risk: none.
        AssertHelp("Message Type ori"::"Warehouse.Receipt.GetSourceDocuments", 'write', true, 'Get Source Documents', 'Sækja upprunaskjöl');
        AssertHelp("Message Type ori"::"Warehouse.Shipment.GetSourceDocuments", 'write', true, 'Get Source Documents', 'Sækja upprunaskjöl');
        AssertHelp("Message Type ori"::"Warehouse.Shipment.Release", 'write', false, 'Releases a warehouse shipment', 'Gefur út vöruhúsaafhendingu');
        AssertHelp("Message Type ori"::"Warehouse.Shipment.Reopen", 'write', false, 'Reopens a released warehouse shipment', 'Opnar útgefna vöruhúsaafhendingu');
        AssertHelp("Message Type ori"::"Warehouse.Request.Get", 'read', true, 'warehouse requests', 'vöruhúsabeiðnir');
        AssertHelp("Message Type ori"::"Warehouse.PostedDocument.Get", 'read', true, 'posted warehouse receipts', 'bókaðar vöruhúsamóttökur');
        AssertHelp("Message Type ori"::"Warehouse.RegisteredActivity.Get", 'read', true, 'registered picks', 'skráðar tínslur, frágang eða tilfærslur');
        AssertHelp("Message Type ori"::"Warehouse.Receipt.Post", 'irreversible', true, 'commits the posting', 'staðfestir bókunina');
        AssertHelp("Message Type ori"::"Warehouse.Shipment.Post", 'irreversible', true, 'commits the posting', 'staðfestir bókunina');
    end;

    /// <summary>The errors chapter lists every refusal code of the issue with its next step.</summary>
    [Test]
    procedure ErrorsChapters_ListRefusalsWithNextSteps()
    begin
        // Stories #51 AC09, #52 AC09, #53 AC11, #54 AC11, #58 AC09 | Time: independent of WorkDate | Risk: none.
        AssertErrorEntry("Message Type ori"::"Warehouse.Receipt.GetSourceDocuments", 'RecordNotFound', 'Create it with Warehouse.Receipt.Create or pass locationCode.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Receipt.GetSourceDocuments", 'PreconditionFailed', 'Release the source documents first; read Warehouse.Request.Get.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Receipt.GetSourceDocuments", 'ConflictingIdentifiers', 'Use a receipt at the same location.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.GetSourceDocuments", 'PreconditionFailed', 'Reopen it with Warehouse.Shipment.Reopen.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.GetSourceDocuments", 'PreconditionFailed', 'Release the source documents first.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.GetSourceDocuments", 'RecordNotFound', 'Create it with Warehouse.Shipment.Create or pass locationCode.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.Release", 'PreconditionFailed', 'Add lines with Warehouse.Shipment.GetSourceDocuments.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.Reopen", 'PreconditionFailed', 'Register or delete the picks first.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.Release", 'UnknownParameter', 'Remove this key or consult Help.Implementation.Get');
        AssertErrorEntry("Message Type ori"::"Warehouse.Request.Get", 'InvalidParameter', 'Use one of the values listed in the help.');
        AssertErrorEntry("Message Type ori"::"Warehouse.PostedDocument.Get", 'RecordNotFound', 'Search with filters instead of a no.');
        AssertErrorEntry("Message Type ori"::"Warehouse.RegisteredActivity.Get", 'RecordNotFound', 'Search with filters instead of a no.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Receipt.Post", 'InvalidLine', 'Read the lines first');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.Post", 'PreconditionFailed', 'register the pick first');
        AssertErrorEntry("Message Type ori"::"Warehouse.Request.Get", 'PermissionDenied', 'BIFROST Whse - Read ori');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.Release", 'PermissionDenied', 'BIFROST Whse - Full ori');
    end;

    /// <summary>A runtime refusal answers in the caller's language: en-US and is-IS.</summary>
    [Test]
    procedure ReleaseRefusal_IsAnsweredInBothLanguages()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        EnglishResponse: JsonObject;
        IcelandicResponse: JsonObject;
        RequestText: Text;
        EnglishRefusalTok: Label 'Warehouse shipment %1 has no lines with a quantity.', Locked = true;
        IcelandicRefusalTok: Label 'Vöruhúsaafhending %1 hefur engar línur með magni.', Locked = true;
    begin
        // Story #53, AC11 | Time: independent of WorkDate | Risk: company language restored before assertions.
        CreateEmptyShipment(ShipmentHeader);
        RequestText := '{"shipmentNo":"' + ShipmentHeader."No." + '"}';

        ReadLocalizedRefusal(1033, RequestText, EnglishResponse);
        ReadLocalizedRefusal(1039, RequestText, IcelandicResponse);

        Assert.AreEqual(StrSubstNo(EnglishRefusalTok, ShipmentHeader."No."), TextValue(EnglishResponse, 'error'), 'English refusal.');
        Assert.AreEqual(StrSubstNo(IcelandicRefusalTok, ShipmentHeader."No."), TextValue(IcelandicResponse, 'error'), 'Icelandic refusal.');
        Assert.AreEqual('Bættu við línum með Warehouse.Shipment.GetSourceDocuments.', TextValue(IcelandicResponse, 'nextStep'), 'Icelandic next step.');
    end;

    local procedure AssertHelp(MessageType: Enum "Message Type ori"; ExpectedEffect: Text; HasParameters: Boolean; EnglishPart: Text; IcelandicPart: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: Interface "Msg Contract ori";
        Discovery: Interface "Msg Discovery ori";
        ContractJson: JsonObject;
        Token: JsonToken;
        Overview: Text;
        OriginalLanguage: Integer;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, ContractJson), MessageTypeName(MessageType) + ' has a contract.');
        Assert.IsTrue(ContractJson.Contains('envelope'), MessageTypeName(MessageType) + ' envelope');
        Assert.IsTrue(ContractJson.Contains('target'), MessageTypeName(MessageType) + ' target');
        Assert.IsTrue(ContractJson.Contains('response'), MessageTypeName(MessageType) + ' response');
        Assert.IsTrue(ContractJson.Contains('errors'), MessageTypeName(MessageType) + ' errors');
        Assert.IsTrue(ContractJson.Contains('related'), MessageTypeName(MessageType) + ' related');
        Assert.IsTrue(ContractJson.Contains('examples'), MessageTypeName(MessageType) + ' examples');
        Assert.AreEqual(HasParameters, ContractJson.Contains('parameters'), MessageTypeName(MessageType) + ' parameters');
        ContractJson.Get('effect', Token);
        Token.AsObject().Get('effect', Token);
        Assert.AreEqual(ExpectedEffect, Token.AsValue().AsText(), MessageTypeName(MessageType) + ' effect');

        Contract := MessageType;
        Discovery := MessageType;
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        Assert.IsTrue(Contract.GetOverview(Overview), MessageTypeName(MessageType) + ' overview');
        Assert.IsTrue(Overview.Contains(EnglishPart), MessageTypeName(MessageType) + ' en-US overview: ' + Overview);
        AssertNoObjectNames(MessageType, Overview);
        Assert.AreNotEqual('', Discovery.GetKeywords(), MessageTypeName(MessageType) + ' keywords');
        GlobalLanguage(1039);
        Assert.IsTrue(Contract.GetOverview(Overview), MessageTypeName(MessageType) + ' overview is-IS');
        GlobalLanguage(OriginalLanguage);
        Assert.IsTrue(Overview.Contains(IcelandicPart), MessageTypeName(MessageType) + ' is-IS overview: ' + Overview);
        AssertNoObjectNames(MessageType, Overview);
    end;

    /// <summary>#67 item 4: every errors entry of Receipt.Post and Shipment.Post carries a nextStep, and InvalidParameterFormat names wrong-typed line values.</summary>
    [Test]
    procedure PostErrorsChapters_CarryNextSteps()
    begin
        // Issue #67, AC2 (item 4) | Time: independent of WorkDate | Risk: none.
        AssertEveryEntryHasNextStep("Message Type ori"::"Warehouse.Receipt.Post", 'qtyToReceive');
        AssertEveryEntryHasNextStep("Message Type ori"::"Warehouse.Shipment.Post", 'qtyToShip');
        AssertErrorEntry("Message Type ori"::"Warehouse.Receipt.Post", 'RecordNotFound', 'Check the number with Data.Records.Get on table Warehouse Receipt Header.');
        AssertErrorEntry("Message Type ori"::"Warehouse.Shipment.Post", 'MultipleErrors', 'Nothing was posted.');
    end;

    /// <summary>#67 item 6: the Icelandic catalogue text of RegisteredActivity calls movements tilfærslur.</summary>
    [Test]
    procedure RegisteredActivity_IcelandicCallsMovementsTilfaerslur()
    var
        Discovery: Interface "Msg Discovery ori";
        MessageTypeInterface: Interface "Msg Interface ori";
        SelectionDescription: Text;
        Description: Text;
        Keywords: Text;
        OriginalLanguage: Integer;
    begin
        // Issue #67, AC2 (item 6) | Time: independent of WorkDate | Risk: none.
        Discovery := "Message Type ori"::"Warehouse.RegisteredActivity.Get";
        MessageTypeInterface := "Message Type ori"::"Warehouse.RegisteredActivity.Get";
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1039);
        SelectionDescription := Discovery.GetSelectionDescription();
        Description := MessageTypeInterface.GetDescription();
        Keywords := Discovery.GetKeywords();
        GlobalLanguage(OriginalLanguage);
        Assert.IsTrue(SelectionDescription.Contains('tínslur, frágang eða tilfærslur'), 'Selection description: ' + SelectionDescription);
        Assert.IsTrue(Description.Contains('tínslur, frágang eða tilfærslur'), 'Description: ' + Description);
        Assert.IsTrue(Keywords.Contains('skráð tilfærsla'), 'Keywords: ' + Keywords);
    end;

    local procedure AssertEveryEntryHasNextStep(MessageType: Enum "Message Type ori"; QtyKey: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        ContractJson: JsonObject;
        Token: JsonToken;
        Entry: JsonToken;
        FormatWhen: Text;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, ContractJson), MessageTypeName(MessageType) + ' has a contract.');
        ContractJson.Get('errors', Token);
        foreach Entry in Token.AsArray() do begin
            Assert.AreNotEqual('', TextValue(Entry.AsObject(), 'nextStep'), MessageTypeName(MessageType) + ' ' + TextValue(Entry.AsObject(), 'code') + ' must carry a nextStep.');
            if TextValue(Entry.AsObject(), 'code') = 'InvalidParameterFormat' then
                FormatWhen := TextValue(Entry.AsObject(), 'when');
        end;
        Assert.IsTrue(FormatWhen.Contains('a line value has the wrong JSON type'), MessageTypeName(MessageType) + ' InvalidParameterFormat names line values: ' + FormatWhen);
        Assert.IsTrue(FormatWhen.Contains(QtyKey), MessageTypeName(MessageType) + ' InvalidParameterFormat names ' + QtyKey + '.');
    end;

    local procedure AssertNoObjectNames(MessageType: Enum "Message Type ori"; HelpText: Text)
    begin
        Assert.IsFalse(HelpText.Contains('Impl'), MessageTypeName(MessageType) + ' help must not name implementation objects.');
        Assert.IsFalse(HelpText.ToLower().Contains('codeunit'), MessageTypeName(MessageType) + ' help must not name codeunits.');
        Assert.IsFalse(HelpText.Contains('1007'), MessageTypeName(MessageType) + ' help must not name object numbers.');
    end;

    local procedure AssertErrorEntry(MessageType: Enum "Message Type ori"; CodeName: Text; NextStepPart: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        ContractJson: JsonObject;
        Token: JsonToken;
        Entry: JsonToken;
        EntryText: Text;
        Found: Boolean;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, ContractJson), MessageTypeName(MessageType) + ' has a contract.');
        ContractJson.Get('errors', Token);
        foreach Entry in Token.AsArray() do begin
            Entry.WriteTo(EntryText);
            if EntryText.Contains('"' + CodeName + '"') and EntryText.Contains(NextStepPart) then
                Found := true;
        end;
        Assert.IsTrue(Found, MessageTypeName(MessageType) + ' must list ' + CodeName + ' with "' + NextStepPart + '".');
    end;

    local procedure CreateEmptyShipment(var ShipmentHeader: Record "Warehouse Shipment Header")
    var
        Location: Record Location;
        Item: Record Item;
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 0);
        ShipmentHeader.Init();
        ShipmentHeader."No." := '';
        ShipmentHeader."Location Code" := Location.Code;
        ShipmentHeader.Insert(true);
    end;

    local procedure ReadLocalizedRefusal(LanguageId: Integer; RequestText: Text; var ResponseJson: JsonObject)
    var
        CompanyInformation: Record "Company Information";
        Language: Record Language;
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        OriginalLanguageCode: Code[10];
        TestLanguageCode: Code[10];
        Succeeded: Boolean;
    begin
        // The public dispatcher uses the company language when Foundation's default is blank.
        if LanguageId = 1039 then
            TestLanguageCode := 'DFIS'
        else
            TestLanguageCode := 'DFEN';
        if not Language.Get(TestLanguageCode) then begin
            Language.Init();
            Language.Code := TestLanguageCode;
            Language.Name := 'Owned document flow locale test';
            Language.Insert();
        end;
        Language."Windows Language ID" := LanguageId;
        Language.Modify();
        CompanyInformation.Get();
        OriginalLanguageCode := CompanyInformation."Default Language Code";
        CompanyInformation."Default Language Code" := Language.Code;
        CompanyInformation.Modify();
        Succeeded := ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Shipment.Release", '', RequestText, ResponseJson, false);
        CompanyInformation."Default Language Code" := OriginalLanguageCode;
        CompanyInformation.Modify();
        Assert.IsTrue(Succeeded, 'Localized request must return JSON.');
    end;

    local procedure MessageTypeName(MessageType: Enum "Message Type ori"): Text
    begin
        exit(Enum::"Message Type ori".Names().Get(Enum::"Message Type ori".Ordinals().IndexOf(MessageType.AsInteger())));
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
