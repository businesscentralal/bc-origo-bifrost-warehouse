namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;

/// <summary>
/// Conformance tests for the twelve Warehouse message type contracts.
/// </summary>
codeunit 97027 "Whse Message Contract Tests ori"
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
        AssertContract("Message Type ori"::"Warehouse.Receipt.Create", 'write', true);
        AssertContract("Message Type ori"::"Warehouse.Receipt.Post", 'irreversible', false);
        AssertContract("Message Type ori"::"Warehouse.Receipt.Post.Preview", 'read', false);
        AssertContract("Message Type ori"::"Warehouse.Pick.Create", 'write', true);
        AssertContract("Message Type ori"::"Warehouse.Pick.Register", 'irreversible', false);
        AssertContract("Message Type ori"::"Warehouse.Putaway.Create", 'write', true);
        AssertContract("Message Type ori"::"Warehouse.Putaway.Register", 'irreversible', false);
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

    local procedure MessageTypeName(MessageType: Enum "Message Type ori"): Text
    begin
        exit(Enum::"Message Type ori".Names().Get(Enum::"Message Type ori".Ordinals().IndexOf(MessageType.AsInteger())));
    end;
}
