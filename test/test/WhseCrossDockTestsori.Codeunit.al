namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Foundation.Company;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Tracking;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.CrossDock;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Ledger;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;
using System.Utilities;

/// <summary>Acceptance tests for #108 through the public dispatcher, including native scope and rollback.</summary>
codeunit 97035 "Whse CrossDock Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
        LibraryInventory: Codeunit "Library - Inventory";
        LibrarySales: Codeunit "Library - Sales";

    /// <summary>AC01: self-made demand is suggested and the posted goods are placed in the cross-dock bin.</summary>
    [Test]
    procedure Scenario_AC01_Demand_PostAndPutaway()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        Posted: Record "Posted Whse. Receipt Header";
        ActivityLine: Record "Warehouse Activity Line";
        Response: JsonObject;
        PurchaseNo: Code[20];
        SalesNo: Code[20];
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Response := Run(Receipt."No.", '{}');
        Helper.AssertSuccess(Response);
        Assert.AreEqual(3, Helper.DecimalValue(Response, 'totalQtyToCrossDock'), Helper.ResponseText(Response));
        Line.SetRange("No.", Receipt."No.");
        Line.FindFirst();
        Assert.AreEqual(3, Line."Qty. to Cross-Dock", 'The sales demand is persisted.');
        Assert.AreEqual(Location."Cross-Dock Bin Code", Line."Cross-Dock Bin Code", 'Cross-dock bin.');
        AssertDemand(Response, SalesNo);
        Response := Helper.RunType(Enum::"Message Type ori"::"Warehouse.Receipt.Post", Receipt."No.", '{"expectedCount":1}');
        Helper.AssertSuccess(Response);
        Posted.SetRange("Whse. Receipt No.", Receipt."No.");
        Posted.FindFirst();
        Response := Helper.RunType(Enum::"Message Type ori"::"Warehouse.Putaway.Create", Posted."No.", '{}');
        Helper.AssertSuccess(Response);
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("Location Code", Location.Code);
        ActivityLine.SetRange("Item No.", Item."No.");
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.SetRange("Bin Code", Location."Cross-Dock Bin Code");
        Assert.IsTrue(ActivityLine.FindFirst(), 'The put-away places demand in the cross-dock bin.');
        Assert.AreEqual(3, ActivityLine.Quantity, 'Cross-dock quantity on put-away.');
    end;

    /// <summary>AC02/AC05: preview returns demand but preserves receipt lines and existing working opportunities.</summary>
    [Test]
    procedure Scenario_AC02_Preview_RollsBack()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        Response: JsonObject;
        PurchaseNo: Code[20];
        SalesNo: Code[20];
        OriginalLine: Text;
        OriginalOpportunity: Text;
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Line.SetRange("No.", Receipt."No.");
        Line.FindFirst();
        SeedOpportunity(Opportunity, Line, 99999);
        OriginalLine := Format(Line);
        OriginalOpportunity := Format(Opportunity);
        Response := Run(Receipt."No.", '{"apply":false}');
        Helper.AssertSuccess(Response);
        Assert.AreEqual(3, Helper.DecimalValue(Response, 'totalQtyToCrossDock'), 'Preview reports sales demand.');
        AssertDemand(Response, SalesNo);
        Line.Get(Line."No.", Line."Line No.");
        Assert.AreEqual(OriginalLine, Format(Line), 'All receipt fields survive preview unchanged.');
        Opportunity.Get('', Receipt."No.", Line."Line No.", 99999);
        Assert.AreEqual(OriginalOpportunity, Format(Opportunity), 'Existing suggestion survives preview unchanged.');
        Opportunity.SetRange("Source Name/No.", Receipt."No.");
        Assert.AreEqual(1, Opportunity.Count(), 'No preview suggestion is persisted.');
    end;

    /// <summary>AC05: selected lines and another receipt are isolated from native working-row replacement.</summary>
    [Test]
    procedure Scenario_AC05_SelectedLines_KeepOtherRows()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        OtherLine: Record "Warehouse Receipt Line";
        OtherReceipt: Record "Warehouse Receipt Header";
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        Response: JsonObject;
        PurchaseNo: Code[20];
        SalesNo: Code[20];
        Original: Text;
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Line.SetRange("No.", Receipt."No.");
        Line.FindFirst();
        OtherLine := Line;
        OtherLine."Line No." += 10000;
        OtherLine."Qty. to Cross-Dock" := 1;
        OtherLine.Insert();
        SeedOpportunity(Opportunity, OtherLine, 99998);
        Original := Format(Opportunity);
        OtherReceipt := Receipt;
        OtherReceipt."No." := CopyStr('X' + Format(CreateGuid(), 0, 4), 1, 20);
        OtherReceipt.Insert();
        OtherLine."No." := OtherReceipt."No.";
        OtherLine.Insert();
        SeedOpportunity(Opportunity, OtherLine, 99997);
        Response := Run(Receipt."No.", '{"lineNos":[' + Format(Line."Line No.", 0, 9) + ']}');
        Helper.AssertSuccess(Response);
        Assert.AreEqual(3, Helper.DecimalValue(Response, 'totalQtyToCrossDock'), 'Only the selected line is calculated.');
        Opportunity.Get('', Receipt."No.", OtherLine."Line No.", 99998);
        Assert.AreEqual(Original, Format(Opportunity), 'Unselected opportunity is untouched.');
        Opportunity.Get('', OtherReceipt."No.", OtherLine."Line No.", 99997);
        OtherLine.Get(Receipt."No.", OtherLine."Line No.");
        Assert.AreEqual(1, OtherLine."Qty. to Cross-Dock", 'Unselected receipt line is untouched.');
        Assert.IsTrue(OtherReceipt.Get(OtherReceipt."No."), 'Other receipt still exists.');
    end;

    /// <summary>AC05: a native failure after writes rolls the whole calculation back.</summary>
    [Test]
    procedure Scenario_AC05_NativeFailure_RollsBack()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        OtherLine: Record "Warehouse Receipt Line";
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        Response: JsonObject;
        PurchaseNo: Code[20];
        SalesNo: Code[20];
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Line.SetRange("No.", Receipt."No.");
        Line.FindFirst();
        SeedOpportunity(Opportunity, Line, 99996);
        Line."Qty. to Receive" := 1;
        Line."Qty. to Receive (Base)" := 1;
        Line.Modify();
        // Native calculation starts with a valid line, then cannot validate the second line's zero UOM.
        OtherLine := Line;
        OtherLine."Line No." += 10000;
        OtherLine."Qty. per Unit of Measure" := 0;
        OtherLine.Insert();
        Response := Run(Receipt."No.", '{}');
        Helper.ExpectError(Response, 'PreconditionFailed', '');
        Line.Get(Line."No.", Line."Line No.");
        Assert.AreEqual(0, Line."Qty. to Cross-Dock", 'Earlier valid line changes roll back.');
        Opportunity.Get('', Receipt."No.", Line."Line No.", 99996);
        Assert.AreEqual(7, Opportunity."Qty. Needed", 'Existing working suggestion rolls back.');
        Assert.IsTrue(Receipt.Get(Receipt."No."), 'Receipt survives.');
    end;

    /// <summary>AC01: no demand returns zero opportunities without inventing demand.</summary>
    [Test]
    procedure Scenario_AC01_NoDemand_ZeroSuggestion()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Purchase: Record "Purchase Header";
        Response: JsonObject;
    begin
        PrepareLocation(Location, Item);
        ReceiptHelper.CreateReleasedPurchaseOrder(Purchase, Item."No.", Location.Code, 5);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(Receipt, Purchase);
        Response := Run(Receipt."No.", '{}');
        Helper.AssertSuccess(Response);
        Assert.AreEqual(0, Helper.DecimalValue(Response, 'totalQtyToCrossDock'), 'No demand.');
    end;

    /// <summary>AC03: a location without cross-docking refuses without changing setup or receipt.</summary>
    [Test]
    procedure Scenario_AC03_DisabledLocation_Refused()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        PurchaseNo: Code[20];
        SalesNo: Code[20];
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Location."Use Cross-Docking" := false;
        Location.Modify();
        Helper.ExpectError(Run(Receipt."No.", '{}'), 'PreconditionFailed', '');
        Location.Get(Location.Code);
        Assert.IsFalse(Location."Use Cross-Docking", 'Setup never changes.');
        Line.SetRange("No.", Receipt."No.");
        Line.FindFirst();
        Assert.AreEqual(0, Line."Qty. to Cross-Dock", 'No receipt change.');
    end;

    /// <summary>AC03: no identifier is a structured refusal.</summary>
    [Test]
    procedure Scenario_AC03_MissingIdentifier_Refused()
    begin
        Helper.ExpectError(Run('', '{}'), 'MissingParameter', '');
    end;

    /// <summary>AC03: a malformed identifier is refused.</summary>
    [Test]
    procedure Scenario_AC03_InvalidIdentifier_Refused()
    begin
        Helper.ExpectError(Run('', '{"systemId":"not-a-guid"}'), 'InvalidParameterFormat', '');
    end;

    /// <summary>AC03: an unknown parameter is refused.</summary>
    [Test]
    procedure Scenario_AC03_UnknownParameter_Refused()
    begin
        Helper.ExpectError(Run('', '{"extra":true}'), 'UnknownParameter', '');
    end;

    /// <summary>AC03: an unknown receipt is refused.</summary>
    [Test]
    procedure Scenario_AC03_MissingReceipt_Refused()
    begin
        Helper.ExpectError(Run('W7-NOT-FOUND', '{}'), 'RecordNotFound', '');
    end;

    /// <summary>AC03: apply accepts only a JSON Boolean.</summary>
    [Test]
    procedure Scenario_AC03_InvalidApply_Refused()
    begin
        Helper.ExpectError(Run('', '{"apply":"false"}'), 'InvalidParameterFormat', '');
        Helper.ExpectError(Run('', '{"apply":null}'), 'InvalidParameterFormat', '');
    end;

    /// <summary>AC03: line selection rejects complex, empty, duplicate and nonpositive numbers before writes.</summary>
    [Test]
    procedure Scenario_AC03_InvalidLines_Refused()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        PurchaseNo: Code[20];
        SalesNo: Code[20];
        Value: Text;
        Cases: List of [Text];
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Line.SetRange("No.", Receipt."No.");
        Line.FindFirst();
        Cases.Add('[]');
        Cases.Add('{}');
        Cases.Add('[0]');
        Cases.Add('[-1]');
        Cases.Add('[1.5]');
        Cases.Add('["10000"]');
        Cases.Add('[null]');
        Cases.Add('[2147483648]');
        Cases.Add('[' + Format(Line."Line No.", 0, 9) + ',' + Format(Line."Line No.", 0, 9) + ']');
        foreach Value in Cases do
            Helper.ExpectError(Run(Receipt."No.", '{"lineNos":' + Value + '}'), 'InvalidParameterFormat', '');
        Line.Get(Line."No.", Line."Line No.");
        Assert.AreEqual(0, Line."Qty. to Cross-Dock", 'No invalid selection writes anything.');
    end;

    /// <summary>AC03: a nonexistent selected line refuses all lines.</summary>
    [Test]
    procedure Scenario_AC03_MissingLine_Refused()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        PurchaseNo: Code[20];
        SalesNo: Code[20];
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Helper.ExpectError(Run(Receipt."No.", '{"lineNos":[2147483647]}'), 'RecordNotFound', '');
    end;

    /// <summary>AC03: different identifiers are refused; aliases of the same receipt work.</summary>
    [Test]
    procedure Scenario_AC03_IdentifierAliases_Conflict()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        Other: Record "Warehouse Receipt Header";
        PurchaseNo: Code[20];
        SalesNo: Code[20];
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Other := Receipt;
        Other."No." := CopyStr('X' + Format(CreateGuid(), 0, 4), 1, 20);
        Other.Insert();
        Helper.ExpectError(Run(Receipt."No.", '{"id":"' + Format(Other.SystemId, 0, 4) + '"}'), 'ConflictingIdentifiers', '');
        Helper.AssertSuccess(Run('', '{"whseReceiptNo":"' + Receipt."No." + '","systemId":"' + Format(Receipt.SystemId, 0, 4) + '","id":"' + Format(Receipt.SystemId, 0, 4) + '"}'));
    end;

    /// <summary>AC02: Omit Commit refuses a preview before writes.</summary>
    [Test]
    procedure Scenario_AC02_OmitCommit_Refused()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        PurchaseNo: Code[20];
        SalesNo: Code[20];
        Response: JsonObject;
    begin
        Prepare(Location, Item, Receipt, PurchaseNo, SalesNo);
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.CalculateCrossDock", Receipt."No.", '{"apply":false}', Response, true), 'JSON response.');
        Helper.ExpectError(Response, 'PreconditionFailed', '');
    end;

    /// <summary>AC04: no receipt-write permission disables and refuses calculation.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Scenario_AC04_NoPermission_Refused()
    var
        TempArgument: Record "Message Argument ori" temporary;
        Implementation: Codeunit "Whse Rcpt CrossDock Impl ori";
        LowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        Assert.IsFalse(Implementation.IsEnabled(), 'No permission disables discovery.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        Implementation.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', '');
    end;

    /// <summary>AC04: discovery translates, help chapters remain English, runtime refusals carry localized nextStep.</summary>
    [Test]
    procedure Scenario_AC04_Bilingual_HelpAndRefusal()
    var
        Implementation: Codeunit "Whse Rcpt CrossDock Impl ori";
        Response: JsonObject;
        EnglishOverview: Text;
        IcelandicOverview: Text;
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        Assert.AreEqual('Calculates cross-dock opportunities on a warehouse receipt; optionally previews without saving.', Implementation.GetDescription(), 'English discovery.');
        Implementation.GetOverview(EnglishOverview);
        GlobalLanguage(1039);
        Assert.AreEqual('Reiknar tækifæri til gegnumstreymis á vöruhúsamóttöku; getur forskoðað án þess að vista.', Implementation.GetDescription(), 'Icelandic discovery.');
        Implementation.GetOverview(IcelandicOverview);
        GlobalLanguage(OriginalLanguage);
        Assert.AreEqual(EnglishOverview, IcelandicOverview, 'Help chapter stays English.');
        GlobalLanguage(1033);
        Response := Run('', '{"apply":"false"}');
        GlobalLanguage(OriginalLanguage);
        Helper.ExpectError(Response, 'InvalidParameterFormat', 'Send text receipt identifiers, true or false for apply, and unique positive integers in lineNos; consult Warehouse.Document.Get.');
        GlobalLanguage(1039);
        Response := Run('', '{"apply":"false"}');
        GlobalLanguage(OriginalLanguage);
        Helper.ExpectError(Response, 'InvalidParameterFormat', 'Sendu móttökuauðkenni sem texta, true eða false fyrir apply og einkvæmar jákvæðar heiltölur í lineNos; skoðaðu Warehouse.Document.Get.');
    end;

    /// <summary>AC01 live-check fixture: run alone with test isolation disabled, then invoke through MCP and run MCPCleanup.</summary>
    [Test]
    procedure Scenario_AC01_MCPSeed()
    var
        Location: Record Location;
        Item: Record Item;
        SalesLine: Record "Sales Line";
        Receipt: Record "Warehouse Receipt Header";
        PurchaseNo: Code[20];
        SalesNo: Code[20];
    begin
        Assert.IsFalse(Location.Get('W7XDMCP'), 'Clean up the previous worker-7 MCP fixture first.');
        PrepareLocation(Location, Item);
        Location.Rename('W7XDMCP');
        Item.Rename('W7XD-MCP');
        PrepareSources(Location, Item, Receipt, PurchaseNo, SalesNo);
        // Test runners and HTTP sessions may have different WorkDate values. An overdue
        // self-made demand remains eligible in both sessions without changing user settings.
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        SalesLine.SetRange("Document No.", SalesNo);
        SalesLine.FindFirst();
        SalesLine."Shipment Date" := DMY2Date(1, 1, 2000);
        SalesLine.Modify();
        Receipt."Vendor Shipment No." := 'WORKER7-108-MCP';
        Receipt.Modify();
        Commit();
        Assert.IsTrue(Receipt.Get(Receipt."No."), 'The live-check fixture is ready.');
    end;

    /// <summary>AC01 live-check cleanup: removes only the dedicated worker-7 location, its unposted sources and masters.</summary>
    [Test]
    procedure Scenario_AC01_MCPCleanup()
    var
        Location: Record Location;
        Item: Record Item;
        Receipt: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        Sales: Record "Sales Header";
        SalesLine: Record "Sales Line";
        Purchase: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        Customer: Record Customer;
        Vendor: Record Vendor;
        WarehouseRequest: Record "Warehouse Request";
        WarehouseEmployee: Record "Warehouse Employee";
        Bin: Record Bin;
        Zone: Record Zone;
        BinContent: Record "Bin Content";
        PostingSetup: Record "Inventory Posting Setup";
        PutawayTemplate: Record "Put-away Template Header";
        PutawayTemplateLine: Record "Put-away Template Line";
        CustomerNo: Code[20];
        VendorNo: Code[20];
    begin
        if not Location.Get('W7XDMCP') then
            exit;
        Assert.IsTrue(Item.Get('W7XD-MCP'), 'Only the named self-seeded fixture may be cleaned.');
        Sales.SetRange("Location Code", Location.Code);
        if Sales.FindSet() then
            repeat
                CustomerNo := Sales."Sell-to Customer No.";
                SalesLine.SetRange("Document Type", Sales."Document Type");
                SalesLine.SetRange("Document No.", Sales."No.");
                SalesLine.DeleteAll(false);
                Sales.Delete(false);
            until Sales.Next() = 0;
        Purchase.SetRange("Location Code", Location.Code);
        if Purchase.FindSet() then
            repeat
                VendorNo := Purchase."Buy-from Vendor No.";
                PurchaseLine.SetRange("Document Type", Purchase."Document Type");
                PurchaseLine.SetRange("Document No.", Purchase."No.");
                PurchaseLine.DeleteAll(false);
                Purchase.Delete(false);
            until Purchase.Next() = 0;
        DeleteFixtureRegisters(Location.Code, Item."No.");
        DeleteFixtureRows(Database::"Warehouse Activity Line", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Warehouse Activity Header", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Posted Whse. Receipt Line", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Posted Whse. Receipt Header", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Purch. Rcpt. Line", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Purch. Rcpt. Header", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Warehouse Entry", 'Location Code', Location.Code);
        DeleteFixtureRows(Database::"Value Entry", 'Item No.', Item."No.");
        DeleteFixtureRows(Database::"Item Ledger Entry", 'Item No.', Item."No.");
        DeleteFixtureRows(Database::"Reservation Entry", 'Item No.', Item."No.");
        Opportunity.SetRange("Location Code", Location.Code);
        Opportunity.DeleteAll(false);
        ReceiptLine.SetRange("Location Code", Location.Code);
        ReceiptLine.DeleteAll(false);
        Receipt.SetRange("Location Code", Location.Code);
        Receipt.DeleteAll(false);
        WarehouseRequest.SetRange("Location Code", Location.Code);
        WarehouseRequest.DeleteAll(false);
        WarehouseEmployee.SetRange("Location Code", Location.Code);
        WarehouseEmployee.DeleteAll(false);
        BinContent.SetRange("Location Code", Location.Code);
        BinContent.DeleteAll(false);
        Bin.SetRange("Location Code", Location.Code);
        Bin.DeleteAll(false);
        Zone.SetRange("Location Code", Location.Code);
        Zone.DeleteAll(false);
        PostingSetup.SetRange("Location Code", Location.Code);
        PostingSetup.DeleteAll(false);
        PutawayTemplateLine.SetRange("Put-away Template Code", Location."Put-away Template Code");
        PutawayTemplateLine.DeleteAll(false);
        if PutawayTemplate.Get(Location."Put-away Template Code") then
            PutawayTemplate.Delete(false);
        Location.Delete(false);
        // All fixture ledger rows are gone. Do not start a native cost adjustment
        // from the delete trigger for this fixture item that is about to be removed.
        Item.Get('W7XD-MCP');
        Item."Cost is Adjusted" := true;
        Item.Modify();
        Item.Delete(true);
        if Customer.Get(CustomerNo) then
            Customer.Delete(true);
        if Vendor.Get(VendorNo) then
            Vendor.Delete(true);
        Commit();
        Assert.IsFalse(Location.Get('W7XDMCP'), 'Live-check location is removed.');
        Assert.IsFalse(Item.Get('W7XD-MCP'), 'Live-check item is removed.');
    end;

    local procedure DeleteFixtureRows(TableNo: Integer; FieldName: Text; Value: Text)
    var
        Reference: RecordRef;
        FieldReference: FieldRef;
        Index: Integer;
        Found: Boolean;
    begin
        Reference.Open(TableNo);
        for Index := 1 to Reference.FieldCount() do begin
            FieldReference := Reference.FieldIndex(Index);
            if FieldReference.Name() = FieldName then begin
                FieldReference.SetRange(Value);
                Found := true;
                break;
            end;
        end;
        Assert.IsTrue(Found, 'Cleanup must have an explicit own-fixture filter.');
        Reference.DeleteAll(false);
        Reference.Close();
    end;

    local procedure DeleteFixtureRegisters(LocationCode: Code[10]; ItemNo: Code[20])
    var
        ItemRegister: Record "Item Register";
        ItemEntry: Record "Item Ledger Entry";
        ItemApplication: Record "Item Application Entry";
        WhseRegister: Record "Warehouse Register";
        WhseEntry: Record "Warehouse Entry";
    begin
        // Receipt posting creates a positive self-application even before any item is shipped.
        // Remove only applications pointing at this fixture's item entries before removing them.
        ItemEntry.SetRange("Item No.", ItemNo);
        if ItemEntry.FindSet() then
            repeat
                ItemApplication.SetRange("Item Ledger Entry No.", ItemEntry."Entry No.");
                ItemApplication.DeleteAll(false);
                Assert.IsTrue(ItemApplication.IsEmpty(), 'Fixture item applications are removed.');
                ItemApplication.Reset();
                ItemApplication.SetRange("Inbound Item Entry No.", ItemEntry."Entry No.");
                ItemApplication.DeleteAll(false);
                ItemApplication.Reset();
                ItemApplication.SetRange("Outbound Item Entry No.", ItemEntry."Entry No.");
                ItemApplication.DeleteAll(false);
                ItemApplication.Reset();
            until ItemEntry.Next() = 0;
        ItemEntry.Reset();
        if ItemRegister.FindSet() then
            repeat
                if ItemEntry.Get(ItemRegister."From Entry No.") then
                    if ItemEntry."Item No." = ItemNo then
                        ItemRegister.Delete(false);
            until ItemRegister.Next() = 0;
        if WhseRegister.FindSet() then
            repeat
                if WhseEntry.Get(WhseRegister."From Entry No.") then
                    if WhseEntry."Location Code" = LocationCode then
                        WhseRegister.Delete(false);
            until WhseRegister.Next() = 0;
    end;

    local procedure PrepareLocation(var Location: Record Location; var Item: Record Item)
    begin
        Helper.SkipCommittedGuidAccounts();
        Helper.CreateDirectedLocation(Location);
        Location.Validate("Use Put-away Worksheet", true);
        Evaluate(Location."Cross-Dock Due Date Calc.", '<7D>');
        Location.Modify(true);
        LibraryInventory.CreateItem(Item);
        Item.Validate("Use Cross-Docking", true);
        Item.Modify(true);
    end;

    local procedure Prepare(var Location: Record Location; var Item: Record Item; var Receipt: Record "Warehouse Receipt Header"; var PurchaseNo: Code[20]; var SalesNo: Code[20])
    begin
        PrepareLocation(Location, Item);
        PrepareSources(Location, Item, Receipt, PurchaseNo, SalesNo);
    end;

    local procedure PrepareSources(var Location: Record Location; var Item: Record Item; var Receipt: Record "Warehouse Receipt Header"; var PurchaseNo: Code[20]; var SalesNo: Code[20])
    var
        Purchase: Record "Purchase Header";
        Sales: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ReleaseSales: Codeunit "Release Sales Document";
    begin

        LibrarySales.CreateSalesHeader(Sales, Sales."Document Type"::Order, '');
        Sales.Validate("Location Code", Location.Code);
        Sales.Modify(true);
        LibrarySales.CreateSalesLine(SalesLine, Sales, SalesLine.Type::Item, Item."No.", 3);
        SalesLine.Validate("Location Code", Location.Code);
        SalesLine.Validate("Shipment Date", WorkDate());
        SalesLine.Modify(true);
        ReleaseSales.Run(Sales);
        SalesNo := Sales."No.";
        ReceiptHelper.CreateReleasedPurchaseOrder(Purchase, Item."No.", Location.Code, 5);
        PurchaseNo := Purchase."No.";
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(Receipt, Purchase);
    end;

    local procedure Run(Subject: Text; Request: Text) Response: JsonObject
    var
        Dispatcher: Codeunit "Dispatcher ori";
        ResponseLog: Codeunit "Temp Blob";
        RequestContent: BigText;
        ResponseContent: BigText;
        LogReference: RecordRef;
        EmptyTaskId: Guid;
        MessageId: Guid;
        ResponseTime: Duration;
        ContentType: Text[100];
        ResponseText: Text;
        LoggedText: Text;
        LoggedResponse: JsonObject;
        LogStream: InStream;
    begin
        Commit();
        RequestContent.AddText(Request);
        Dispatcher.EnqueueAndProcess(Enum::"Message Type ori"::"Warehouse.Receipt.CalculateCrossDock", Enum::"Message Version ori"::"1.0", CopyStr(Subject, 1, 250),
            'Warehouse #108 acceptance test', 'text/json', RequestContent, EmptyTaskId, GlobalLanguage(), MessageId, ResponseContent, ContentType, ResponseTime);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        Assert.IsTrue(Response.ReadFrom(ResponseText), 'Response is JSON.');
        if Helper.TextValue(Response, 'status') <> 'Error' then
            exit;
        // Foundation owns table 10077897 (Message ori); the supported dispatcher returns this exact entry ID.
        // RecordRef is used only in this test to verify the persisted error response, never in product code.
        LogReference.Open(10077897);
        LogReference.Field(1).SetRange(MessageId);
        Assert.IsTrue(LogReference.FindFirst(), 'The refusal is logged by Foundation.');
        ResponseLog.FromRecordRef(LogReference, 9);
        LogReference.Close();
        ResponseLog.CreateInStream(LogStream, TextEncoding::UTF8);
        LogStream.ReadText(LoggedText);
        Assert.IsTrue(LoggedResponse.ReadFrom(LoggedText), 'The error log stores JSON.');
        Assert.AreEqual('Error', Helper.TextValue(LoggedResponse, 'status'), 'Foundation stores an error entry.');
        Assert.AreEqual(Helper.TextValue(Response, 'code'), Helper.TextValue(LoggedResponse, 'code'), 'The logged error code matches.');
        Assert.AreNotEqual('', Helper.TextValue(LoggedResponse, 'nextStep'), 'The logged refusal includes nextStep.');
    end;

    local procedure SeedOpportunity(var Opportunity: Record "Whse. Cross-Dock Opportunity"; Line: Record "Warehouse Receipt Line"; EntryNo: Integer)
    begin
        Opportunity.Init();
        Opportunity."Source Template Name" := '';
        Opportunity."Source Name/No." := Line."No.";
        Opportunity."Source Line No." := Line."Line No.";
        Opportunity."Line No." := EntryNo;
        Opportunity."Location Code" := Line."Location Code";
        Opportunity."Item No." := Line."Item No.";
        Opportunity."Qty. Needed" := 7;
        Opportunity.Insert();
    end;

    local procedure AssertDemand(Response: JsonObject; SalesNo: Code[20])
    var
        Token: JsonToken;
        LineToken: JsonToken;
        Opportunities: JsonToken;
        Opportunity: JsonToken;
    begin
        Response.Get('lines', Token);
        Token.AsArray().Get(0, LineToken);
        LineToken.AsObject().Get('opportunities', Opportunities);
        Assert.IsTrue(Opportunities.AsArray().Count() > 0, 'Demand opportunities returned.');
        Opportunities.AsArray().Get(0, Opportunity);
        Assert.AreEqual(SalesNo, Helper.TextValue(Opportunity.AsObject(), 'sourceNo'), 'Self-made sales demand is identified.');
        Assert.AreEqual(3, Helper.DecimalValue(Opportunity.AsObject(), 'qtyNeeded'), 'Demand quantity.');
    end;
}
