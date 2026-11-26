namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Service.Document;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>Issue 112 shipment service-source tests through the public message dispatcher.</summary>
codeunit 97095 "Whse Service Source Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryApplicationArea: Codeunit "Library - Application Area";
        LibrarySales: Codeunit "Library - Sales";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>AC01/AC04: a released service order creates a warehouse shipment.</summary>
    [Test]
    procedure AC01_CreateServiceShipment()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, true);
        RunCreate(ServiceHeader."No.", Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        AssertServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC01: a service order may carry its shipment location on the lines only.</summary>
    [Test]
    procedure AC01_ServiceLineLocationWithoutHeader()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        ReleaseServiceDocument: Codeunit "Release Service Document";
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, false);
        ServiceHeader."Location Code" := '';
        ServiceHeader.Modify(true);
        ReleaseServiceDocument.PerformManualRelease(ServiceHeader);
        RunCreate(ServiceHeader."No.", Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        AssertServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC04: a conflicting location filter refuses the order without creating shipment lines.</summary>
    [Test]
    procedure AC04_ConflictingLocationIsRefused()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, true);
        ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Shipment.Create", '', '{"sourceDocuments":[{"sourceType":"ServiceOrder","documentNo":"' + ServiceHeader."No." + '"}],"locationCode":"BIF112NONE"}', Response);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(Response, 'code'), ResponseText(Response));
        Assert.IsTrue(TextValue(Response, 'nextStep') <> '', 'A location correction is required.');
        AssertNoServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC01/AC04: source-document selection adds service order lines.</summary>
    [Test]
    procedure AC01_GetServiceSourceDocuments()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, true);
        RunGetSources(ServiceHeader."No.", Location.Code, 'Service Order', Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        AssertServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC01: an omitted source filter includes service orders for a Premium caller.</summary>
    [Test]
    procedure AC01_DefaultSourcesIncludeService()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, true);
        RunGetSources(ServiceHeader."No.", Location.Code, '', Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        AssertServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC04: a service order that has not been released is refused with a next step.</summary>
    [Test]
    procedure AC04_UnreleasedServiceIsRefused()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, false);
        RunCreate(ServiceHeader."No.", Response);
        Assert.AreEqual('PreconditionFailed', TextValue(Response, 'code'), ResponseText(Response));
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Release'), 'The next step must explain release.');
        AssertNoServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC04: a missing service order is not replaced by a different source document.</summary>
    [Test]
    procedure AC04_MissingServiceIsRefused()
    var
        Response: JsonObject;
    begin
        LibraryApplicationArea.EnablePremiumSetup();
        RunCreate('BIF112-MISSING', Response);
        Assert.AreEqual('RecordNotFound', TextValue(Response, 'code'), ResponseText(Response));
    end;

    /// <summary>AC04: a second source-document selection does not duplicate service lines.</summary>
    [Test]
    procedure AC04_ExistingServiceLinesNotDuplicated()
    var
        ServiceHeader: Record "Service Header";
        Location: Record Location;
        Response: JsonObject;
    begin
        PrepareServiceOrder(ServiceHeader, Location, true);
        RunCreate(ServiceHeader."No.", Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        RunGetSources(ServiceHeader."No.", Location.Code, 'Service Order', Response);
        AssertServiceLine(ServiceHeader."No.");
    end;

    /// <summary>AC02: service creation is refused before document lookup in an Essentials company.</summary>
    [Test]
    procedure AC02_EssentialCreateRefused()
    var
        Response: JsonObject;
    begin
        LibraryApplicationArea.EnableEssentialSetup();
        RunCreate('BIF112-MISSING', Response);
        AssertPremiumRefusal(Response);
    end;

    /// <summary>AC02: an explicit service filter is refused in an Essentials company.</summary>
    [Test]
    procedure AC02_EssentialGetSourcesRefused()
    var
        Location: Record Location;
        Item: Record Item;
        Response: JsonObject;
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 0);
        LibraryApplicationArea.EnableEssentialSetup();
        RunGetSources('BIF112-MISSING', Location.Code, 'Service Order', Response);
        AssertPremiumRefusal(Response);
    end;

    /// <summary>AC02/AC04: sales shipment creation remains available in an Essentials company.</summary>
    [Test]
    procedure AC02_EssentialSalesCreateUnchanged()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        Response: JsonObject;
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 0);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 2);
        LibraryApplicationArea.EnableEssentialSetup();
        ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Shipment.Create", '', '{"sourceDocuments":[{"sourceType":"SalesOrder","documentNo":"' + SalesHeader."No." + '"}]}', Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
    end;

    /// <summary>AC02/AC04: default selection still creates sales shipment lines without Premium.</summary>
    [Test]
    procedure AC02_EssentialSalesSelectionUnchanged()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        Response: JsonObject;
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 0);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 2);
        LibraryApplicationArea.EnableEssentialSetup();
        RunGetSources(SalesHeader."No.", Location.Code, '', Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
    end;

    /// <summary>AC03: service availability refusals are localized in both supported languages.</summary>
    [Test]
    procedure AC03_BilingualServiceRefusal()
    var
        Response: JsonObject;
    begin
        LibraryApplicationArea.EnableEssentialSetup();
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.Shipment.Create", '{"sourceDocuments":[{"sourceType":"ServiceOrder","documentNo":"BIF112-MISSING"}]}', 1033, Response), 'English JSON response.');
        AssertPremiumRefusal(Response);
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Ask an administrator'), 'English next step.');
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.Shipment.Create", '{"sourceDocuments":[{"sourceType":"ServiceOrder","documentNo":"BIF112-MISSING"}]}', 1039, Response), 'Icelandic JSON response.');
        AssertPremiumRefusal(Response);
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Biddu stjórnanda'), 'Icelandic next step.');
    end;

    /// <summary>AC03: discovery names service orders and the English contract declares the source.</summary>
    [Test]
    procedure AC03_DiscoveryAndContractNameService()
    var
        CreateImpl: Codeunit "Whse Shipment Create Impl ori";
        SourcesImpl: Codeunit "Whse Ship GetSrcDocs Impl ori";
        Parameters: JsonArray;
        ContractText: Text;
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        Assert.IsTrue(CreateImpl.GetDescription().Contains('Service Order'), 'English create discovery.');
        CreateImpl.GetParameters(Parameters);
        Parameters.WriteTo(ContractText);
        Assert.IsTrue(ContractText.Contains('ServiceOrder'), 'Create source contract.');
        Clear(Parameters);
        SourcesImpl.GetParameters(Parameters);
        Parameters.WriteTo(ContractText);
        Assert.IsTrue(ContractText.Contains('Service Order'), 'Get sources contract.');
        GlobalLanguage(1039);
        Assert.IsTrue(CreateImpl.GetDescription().Contains('þjónustupöntun'), 'Icelandic create discovery.');
        Assert.IsTrue(SourcesImpl.GetSelectionDescription().Contains('þjónustupöntunum'), 'Icelandic selection discovery.');
        GlobalLanguage(OriginalLanguage);
    end;

    local procedure PrepareServiceOrder(var ServiceHeader: Record "Service Header"; var Location: Record Location; ReleaseDocument: Boolean)
    var
        Item: Record Item;
        Customer: Record Customer;
        ServiceLine: Record "Service Line";
        ReleaseServiceDocument: Codeunit "Release Service Document";
    begin
        LibraryApplicationArea.EnablePremiumSetup();
        ShipmentHelper.SetupLocationAndItem(Location, Item, 0);
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibrarySales.CreateCustomer(Customer);
        ServiceHeader.Init();
        ServiceHeader.Validate("Document Type", ServiceHeader."Document Type"::Order);
        ServiceHeader.Insert(true);
        ServiceHeader.Validate("Customer No.", Customer."No.");
        ServiceHeader.Validate("Location Code", Location.Code);
        ServiceHeader.Modify(true);
        ServiceLine.Init();
        ServiceLine.Validate("Document Type", ServiceHeader."Document Type");
        ServiceLine.Validate("Document No.", ServiceHeader."No.");
        ServiceLine."Line No." := 10000;
        ServiceLine.Insert(true);
        ServiceLine.Validate(Type, ServiceLine.Type::Item);
        ServiceLine.Validate("No.", Item."No.");
        ServiceLine.Validate("Location Code", Location.Code);
        ServiceLine.Validate(Quantity, 2);
        ServiceLine.Modify(true);
        if ReleaseDocument then
            ReleaseServiceDocument.PerformManualRelease(ServiceHeader);
    end;

    local procedure RunCreate(DocumentNo: Code[20]; var Response: JsonObject)
    begin
        // The message dispatcher is the user surface; this story adds no pages or page actions.
        Clear(Response);
        Assert.IsTrue(ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Shipment.Create", '', '{"sourceDocuments":[{"sourceType":"ServiceOrder","documentNo":"' + DocumentNo + '"}]}', Response), 'JSON response.');
    end;

    local procedure RunGetSources(DocumentNo: Code[20]; LocationCode: Code[10]; SourceDocument: Text; var Response: JsonObject)
    begin
        Clear(Response);
        Assert.IsTrue(ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Shipment.GetSourceDocuments", '', '{"locationCode":"' + LocationCode + '","sourceDocument":"' + SourceDocument + '","sourceNos":["' + DocumentNo + '"]}', Response), 'JSON response.');
    end;

    local procedure AssertServiceLine(DocumentNo: Code[20])
    var
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        ShipmentLine.SetRange("Source Type", Database::"Service Line");
        ShipmentLine.SetRange("Source No.", DocumentNo);
        Assert.RecordCount(ShipmentLine, 1);
        ShipmentLine.FindFirst();
        Assert.AreEqual(2, ShipmentLine.Quantity, 'The service quantity is preserved.');
    end;

    local procedure AssertNoServiceLine(DocumentNo: Code[20])
    var
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        ShipmentLine.SetRange("Source Type", Database::"Service Line");
        ShipmentLine.SetRange("Source No.", DocumentNo);
        Assert.RecordCount(ShipmentLine, 0);
    end;

    local procedure AssertPremiumRefusal(Response: JsonObject)
    begin
        Assert.AreEqual('PreconditionFailed', TextValue(Response, 'code'), ResponseText(Response));
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Premium'), 'A useful Premium next step is required.');
    end;

    local procedure TextValue(Response: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Response.Get(KeyName, Token) then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure ResponseText(Response: JsonObject) Written: Text
    begin
        Response.WriteTo(Written);
    end;
}
