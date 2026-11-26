namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Service.Document;
using Microsoft.Warehouse.Activity;
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

    /// <summary>AC01/AC04: service parts are picked from a native warehouse shipment.</summary>
    [Test]
    procedure AC01_ServiceShipmentCreatesWarehousePick()
    var
        ServiceHeader: Record "Service Header";
        ServiceLine: Record "Service Line";
        Location: Record Location;
        ShipmentLine: Record "Warehouse Shipment Line";
        ActivityLine: Record "Warehouse Activity Line";
        ReleaseServiceDocument: Codeunit "Release Service Document";
        Response: JsonObject;
    begin
        // Story #112, AC01/AC04 | Time: WorkDate for stock posting | Risk: native service warehouse integration.
        // [GIVEN] A service order with stock at a shipment-and-pick location.
        PrepareServiceOrder(ServiceHeader, Location, false);
        Location.Validate("Require Pick", true);
        Location.Modify(true);
        ServiceLine.Get(ServiceHeader."Document Type", ServiceHeader."No.", 10000);
        ShipmentHelper.CreatePositiveAdjustment(ServiceLine."No.", Location.Code, 10);
        ReleaseServiceDocument.PerformManualRelease(ServiceHeader);
        RunCreate(ServiceHeader."No.", Response);
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        ShipmentLine.SetRange("Source Type", Database::"Service Line");
        ShipmentLine.SetRange("Source No.", ServiceHeader."No.");
        ShipmentLine.FindFirst();
        // [WHEN] The user creates the warehouse pick through the public dispatcher.
        Assert.IsTrue(ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Pick.Create", ShipmentLine."No.", '{}', Response), 'Pick JSON response.');
        // [THEN] The created pick retains the service source and the complete requested quantity.
        Assert.AreEqual('Success', TextValue(Response, 'status'), ResponseText(Response));
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", TextValue(Response, 'pickNo'));
        ActivityLine.SetRange("Source Type", Database::"Service Line");
        ActivityLine.SetRange("Source No.", ServiceHeader."No.");
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Take);
        Assert.IsTrue(ActivityLine.FindFirst(), 'Service pick take line exists.');
        Assert.AreEqual(2, ActivityLine.Quantity, 'Service quantity to pick.');
    end;

    /// <summary>AC01/AC03: creating a service inventory pick refuses both source spellings in both languages.</summary>
    [Test]
    procedure AC01_ServiceInventoryCreateRefusedBilingually()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Response: JsonObject;
        BeforeCount: Integer;
    begin
        // Story #112, AC01/AC03 | Time: independent | Risk: none; no service data is read.
        // [GIVEN] No service order is required to reject this unsupported source.
        BeforeCount := ActivityHeader.Count();
        // [WHEN] The caller requests an inventory pick, including a source with no identifier.
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.InventoryPick.Create", '{"sourceDocument":"Service Order","sourceNo":"X112-NOT-FOUND"}', 1033, Response), 'English JSON response.');
        AssertInventoryPickRefusal(Response, 1033);
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.InventoryPick.Create", '{"sourceDocument":"ServiceOrder"}', 1039, Response), 'Icelandic JSON response.');
        AssertInventoryPickRefusal(Response, 1039);
        // [THEN] No pick is created and the supported alternative is given.
        Assert.AreEqual(BeforeCount, ActivityHeader.Count(), 'Refusal must not create a pick.');
    end;

    /// <summary>AC01/AC04: imported service inventory picks cannot post, by number or SystemId.</summary>
    [Test]
    procedure AC01_ServiceInventoryPostRefusedBilingually()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Response: JsonObject;
    begin
        // Story #112, AC01/AC03/AC04 | Time: independent | Risk: imported unsupported activities.
        // [GIVEN] A deliberately invalid imported inventory-pick header with a service source.
        SeedServiceInventoryPick(ActivityHeader);
        // [WHEN] Post is invoked by each supported identifier form through the public dispatcher.
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.InventoryPick.Post", '{"pickNo":"' + ActivityHeader."No." + '"}', 1033, Response), 'English JSON response.');
        AssertInventoryPickRefusal(Response, 1033);
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.InventoryPick.Post", '{"systemId":"' + Format(ActivityHeader.SystemId, 0, 4) + '"}', 1039, Response), 'Icelandic JSON response.');
        AssertInventoryPickRefusal(Response, 1039);
        // [THEN] The unsupported activity remains untouched.
        ActivityHeader.Get(ActivityHeader.Type, ActivityHeader."No.");
        Assert.AreEqual(ActivityHeader."Source Document"::"Service Order", ActivityHeader."Source Document", 'Header is unchanged.');
    end;

    /// <summary>AC04: a service line is refused even when its imported header has no service source.</summary>
    [Test]
    procedure AC04_ServiceInventoryLineOnlyRefused()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Response: JsonObject;
    begin
        // Story #112, AC04 | Time: independent | Risk: inconsistent imported activities.
        // [GIVEN] Only the line identifies the service source.
        SeedServiceInventoryPick(ActivityHeader);
        Clear(ActivityHeader."Source Document");
        ActivityHeader.Modify();
        ActivityLine.Init();
        ActivityLine."Activity Type" := ActivityHeader.Type;
        ActivityLine."No." := ActivityHeader."No.";
        ActivityLine."Line No." := 10000;
        ActivityLine."Source Type" := Database::"Service Line";
        ActivityLine.Insert();
        // [WHEN] Posting is requested.
        Assert.IsTrue(ShipmentHelper.RunLocalizedMessage("Message Type ori"::"Warehouse.InventoryPick.Post", '{"pickNo":"' + ActivityHeader."No." + '"}', 1033, Response), 'JSON response.');
        // [THEN] The service line is refused before quantity changes or posting.
        AssertInventoryPickRefusal(Response, 1033);
        ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", 10000);
        Assert.AreEqual(Database::"Service Line", ActivityLine."Source Type", 'Line is unchanged.');
    end;

    /// <summary>AC03: inventory-pick discovery and English error chapters explain the service alternative.</summary>
    [Test]
    procedure AC03_InventoryPickHelpNamesServiceFlow()
    var
        CreateImpl: Codeunit "Whse InvtPick Create Impl ori";
        PostImpl: Codeunit "Whse InvtPick Post Impl ori";
        Errors: JsonArray;
        Written: Text;
        OriginalLanguage: Integer;
    begin
        // Story #112, AC03 | Time: independent | Risk: none; discovery has no page surface.
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        Assert.IsTrue(CreateImpl.GetSelectionDescription().Contains('Service orders'), 'English create discovery.');
        Assert.IsTrue(PostImpl.GetSelectionDescription().Contains('Service orders'), 'English post discovery.');
        CreateImpl.GetErrors(Errors);
        Errors.WriteTo(Written);
        Assert.IsTrue(Written.Contains('Warehouse.Shipment.Create'), 'Create error chapter gives service alternative.');
        Clear(Errors);
        PostImpl.GetErrors(Errors);
        Errors.WriteTo(Written);
        Assert.IsTrue(Written.Contains('Warehouse.Pick.Register'), 'Post error chapter gives service alternative.');
        GlobalLanguage(1039);
        Assert.IsTrue(CreateImpl.GetSelectionDescription().Contains('Þjónustupantanir'), 'Icelandic create discovery.');
        Assert.IsTrue(PostImpl.GetSelectionDescription().Contains('Þjónustupantanir'), 'Icelandic post discovery.');
        GlobalLanguage(OriginalLanguage);
    end;

    local procedure SeedServiceInventoryPick(var ActivityHeader: Record "Warehouse Activity Header")
    begin
        ActivityHeader.Init();
        ActivityHeader.Type := ActivityHeader.Type::"Invt. Pick";
        ActivityHeader."No." := CopyStr('X' + DelChr(Format(CreateGuid(), 0, 4), '=', '{}-'), 1, MaxStrLen(ActivityHeader."No."));
        ActivityHeader."Source Document" := ActivityHeader."Source Document"::"Service Order";
        ActivityHeader.Insert();
    end;

    local procedure AssertInventoryPickRefusal(Response: JsonObject; LanguageId: Integer)
    begin
        Assert.AreEqual('PreconditionFailed', TextValue(Response, 'code'), ResponseText(Response));
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Warehouse.Shipment.Create'), 'Shipment next step.');
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Warehouse.Pick.Create'), 'Pick creation next step.');
        Assert.IsTrue(TextValue(Response, 'nextStep').Contains('Warehouse.Pick.Register'), 'Pick registration next step.');
        if LanguageId = 1039 then
            Assert.IsTrue(TextValue(Response, 'nextStep').Contains('þjónustupöntunina'), 'Icelandic next step.')
        else
            Assert.IsTrue(TextValue(Response, 'nextStep').Contains('service order'), 'English next step.');
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
