namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Assembly.Document;
using Microsoft.Inventory.BOM;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Microsoft.Manufacturing.Document;
using Microsoft.Projects.Project.Job;
using Microsoft.Projects.Project.Planning;
using Microsoft.Warehouse.Activity;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Pick.Create with sourceType (#111 AC01, AC05): a pick for the components of a released
/// production order, and the refusals of the new keys. Orders, items and locations are created by the test.
/// </summary>
codeunit 97094 "Whse Pick Source Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryAssembly: Codeunit "Library - Assembly";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryJob: Codeunit "Library - Job";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        Helper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>sourceType productionOrder creates a pick for the component, and Warehouse.Pick.Register registers it.</summary>
    [Test]
    procedure Create_ProductionOrder_CreatesPickThatRegisters()
    var
        ProductionOrder: Record "Production Order";
        ComponentItem: Record Item;
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PrepareProductionOrder(ProductionOrder, ComponentItem, true);

        Run(SourceRequest('productionOrder', ProductionOrder."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('productionOrder', TextValue(ResponseJson, 'sourceType'), 'The source type should be returned.');
        Assert.AreEqual(ProductionOrder."No.", TextValue(ResponseJson, 'sourceNo'), 'The order number should be returned.');
        Assert.AreEqual('', TextValue(ResponseJson, 'whseShipmentNo'), 'No shipment is involved.');
        PickNo := CopyStr(TextValue(ResponseJson, 'pickNo'), 1, MaxStrLen(PickNo));
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo), 'The warehouse pick should exist.');
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", PickNo);
        ActivityLine.FindFirst();
        Assert.AreEqual(ActivityLine."Source Document"::"Prod. Consumption", ActivityLine."Source Document", 'The pick should be for production consumption.');
        Assert.AreEqual(ComponentItem."No.", ActivityLine."Item No.", 'The pick should take the component.');

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", PickNo, '{}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsFalse(ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo), 'The registered pick should be gone.');
    end;

    /// <summary>At a directed location, sourceType productionOrder creates a pick to the to-production bin, and registering it marks the component picked (#111 AC01).</summary>
    [Test]
    procedure Create_ProductionOrderDirected_RegistersToProductionBin()
    var
        ProductionOrder: Record "Production Order";
        ComponentItem: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
        ProdOrderComponent: Record "Prod. Order Component";
        ResponseJson: JsonObject;
        PickNo: Code[20];
        ToProductionBinCode: Code[20];
    begin
        PrepareDirectedProductionOrder(ProductionOrder, ComponentItem, ToProductionBinCode);

        Run(SourceRequest('productionOrder', ProductionOrder."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        PickNo := CopyStr(TextValue(ResponseJson, 'pickNo'), 1, MaxStrLen(PickNo));
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", PickNo);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Place);
        ActivityLine.FindFirst();
        Assert.AreEqual(ToProductionBinCode, ActivityLine."Bin Code", 'The pick should place the component in the to-production bin.');

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", PickNo, '{}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        ProdOrderComponent.SetRange(Status, ProductionOrder.Status);
        ProdOrderComponent.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderComponent.SetRange("Item No.", ComponentItem."No.");
        ProdOrderComponent.FindFirst();
        Assert.AreEqual(2, ProdOrderComponent."Qty. Picked", 'The registered pick should mark the component as picked.');
        Assert.AreEqual(ToProductionBinCode, ProdOrderComponent."Bin Code", 'The component should be consumed from the to-production bin.');
    end;

    /// <summary>sourceType assemblyOrder creates a pick for the assembly component of a released assembly order (#111 AC02).</summary>
    [Test]
    procedure Create_AssemblyOrder_CreatesPick()
    var
        AssemblyHeader: Record "Assembly Header";
        ComponentItem: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PrepareAssemblyOrder(AssemblyHeader, ComponentItem);

        Run(SourceRequest('assemblyOrder', AssemblyHeader."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('assemblyOrder', TextValue(ResponseJson, 'sourceType'), 'The source type should be returned.');
        PickNo := CopyStr(TextValue(ResponseJson, 'pickNo'), 1, MaxStrLen(PickNo));
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", PickNo);
        ActivityLine.FindFirst();
        Assert.AreEqual(ActivityLine."Source Document"::"Assembly Consumption", ActivityLine."Source Document", 'The pick should be for assembly consumption.');
        Assert.AreEqual(ComponentItem."No.", ActivityLine."Item No.", 'The pick should take the component.');
    end;

    /// <summary>sourceType project creates a pick for the item planning line of a project (#111 AC02).</summary>
    [Test]
    procedure Create_Project_CreatesPick()
    var
        Job: Record Job;
        ComponentItem: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PrepareProject(Job, ComponentItem);

        Run(SourceRequest('project', Job."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('project', TextValue(ResponseJson, 'sourceType'), 'The source type should be returned.');
        Assert.AreEqual(Job."No.", TextValue(ResponseJson, 'sourceNo'), 'The project number should be returned.');
        PickNo := CopyStr(TextValue(ResponseJson, 'pickNo'), 1, MaxStrLen(PickNo));
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", PickNo);
        ActivityLine.FindFirst();
        Assert.AreEqual(ActivityLine."Source Document"::"Job Usage", ActivityLine."Source Document", 'The pick should be for project usage.');
        Assert.AreEqual(ComponentItem."No.", ActivityLine."Item No.", 'The pick should take the planned item.');
    end;

    /// <summary>A second call creates nothing new and is refused with PreconditionFailed instead of returning the older pick.</summary>
    [Test]
    procedure Create_ProductionOrderTwice_SecondIsRefused()
    var
        ProductionOrder: Record "Production Order";
        ComponentItem: Record Item;
        ResponseJson: JsonObject;
    begin
        PrepareProductionOrder(ProductionOrder, ComponentItem, true);
        Run(SourceRequest('productionOrder', ProductionOrder."No."), '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));

        // Business Central refuses the second pick with an error; outside Omit Commit the type answers it.
        Clear(ResponseJson);
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Create", '', SourceRequest('productionOrder', ProductionOrder."No."), ResponseJson, false), 'The response should be JSON.');

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(1, CountPicks(ProductionOrder."No."), 'Only the first pick should exist.');
    end;

    /// <summary>A firm planned order is refused as not released and gets no pick.</summary>
    [Test]
    procedure Create_FirmPlannedOrder_IsRefused()
    var
        ProductionOrder: Record "Production Order";
        ComponentItem: Record Item;
        ResponseJson: JsonObject;
    begin
        PrepareProductionOrder(ProductionOrder, ComponentItem, false);

        Run(SourceRequest('productionOrder', ProductionOrder."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Release the order first, then send the request again.', TextValue(ResponseJson, 'nextStep'), 'The next step should name release.');
        Assert.AreEqual(0, CountPicks(ProductionOrder."No."), 'Nothing should be created.');
    end;

    /// <summary>An unknown sourceType is refused with the valid values.</summary>
    [Test]
    procedure Create_UnknownSourceType_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run(SourceRequest('serviceOrder', 'X'), '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send sourceType shipment, productionOrder, assemblyOrder or project.', TextValue(ResponseJson, 'nextStep'), 'The next step should list the source types.');
    end;

    /// <summary>sourceType without sourceNo, and sourceNo without sourceType, are refused as missing.</summary>
    [Test]
    procedure Create_MissingSourceNoOrType_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceType":"assemblyOrder"}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceNo', TextValue(ResponseJson, 'parameter'), 'The missing key should be sourceNo.');

        Run('{"sourceNo":"X"}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceType', TextValue(ResponseJson, 'parameter'), 'The missing key should be sourceType.');
    end;

    /// <summary>sourceType with a shipment identifier or a subject is refused as conflicting.</summary>
    [Test]
    procedure Create_SourceTypeWithShipmentKey_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceType":"project","sourceNo":"X","whseShipmentNo":"SH1"}', '', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run(SourceRequest('project', 'X'), 'SH1', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    /// <summary>An order number that does not exist is refused as not found.</summary>
    [Test]
    procedure Create_UnknownOrder_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run(SourceRequest('productionOrder', CopyStr(LibraryUtility.GenerateGUID(), 1, 20)), '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run(SourceRequest('assemblyOrder', CopyStr(LibraryUtility.GenerateGUID(), 1, 20)), '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run(SourceRequest('project', CopyStr(LibraryUtility.GenerateGUID(), 1, 20)), '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    /// <summary>sourceType shipment keeps the shipment behaviour; with sourceNo it conflicts.</summary>
    [Test]
    procedure Create_ShipmentSourceWithSourceNo_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceType":"shipment","sourceNo":"X"}', '', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    local procedure PrepareProductionOrder(var ProductionOrder: Record "Production Order"; var ComponentItem: Record Item; Release: Boolean)
    var
        Location: Record Location;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, true, false, true);
        Location.Validate("Prod. Consump. Whse. Handling", Location."Prod. Consump. Whse. Handling"::"Warehouse Pick (mandatory)");
        Location.Modify(true);
        Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(ComponentItem);
        Helper.CreatePositiveAdjustment(ComponentItem."No.", Location.Code, 5);
        CreateProductionOrderAt(Location.Code, ProductionOrder, ComponentItem, Release);
    end;

    local procedure PrepareDirectedProductionOrder(var ProductionOrder: Record "Production Order"; var ComponentItem: Record Item; var ToProductionBinCode: Code[20])
    var
        Location: Record Location;
        PickBin: Record Bin;
        ProductionBin: Record Bin;
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        if Location."To-Production Bin Code" = '' then begin
            LibraryWarehouse.FindBin(ProductionBin, Location.Code, 'PRODUCTION', 1);
            Location.Validate("To-Production Bin Code", ProductionBin.Code);
        end;
        Location.Validate("Prod. Consump. Whse. Handling", Location."Prod. Consump. Whse. Handling"::"Warehouse Pick (mandatory)");
        Location.Modify(true);
        ToProductionBinCode := Location."To-Production Bin Code";
        Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(ComponentItem);
        LibraryWarehouse.FindBin(PickBin, Location.Code, 'PICK', 1);
        LibraryWarehouse.UpdateInventoryInBinUsingWhseJournal(PickBin, ComponentItem."No.", 5, false);
        CreateProductionOrderAt(Location.Code, ProductionOrder, ComponentItem, true);
    end;

    local procedure CreateProductionOrderAt(LocationCode: Code[10]; var ProductionOrder: Record "Production Order"; ComponentItem: Record Item; Release: Boolean)
    var
        ParentItem: Record Item;
        FirmPlannedOrder: Record "Production Order";
        ProdOrderLine: Record "Prod. Order Line";
        ProdOrderComponent: Record "Prod. Order Component";
    begin
        LibraryInventory.CreateItem(ParentItem);
        ParentItem.Validate("Replenishment System", ParentItem."Replenishment System"::"Prod. Order");
        ParentItem.Modify(true);
        LibraryManufacturing.CreateProductionOrder(FirmPlannedOrder, FirmPlannedOrder.Status::"Firm Planned", FirmPlannedOrder."Source Type"::Item, ParentItem."No.", 2);
        FirmPlannedOrder.Validate("Location Code", LocationCode);
        FirmPlannedOrder.Modify(true);
        LibraryManufacturing.RefreshProdOrder(FirmPlannedOrder, false, true, false, false, false);
        ProdOrderLine.SetRange(Status, FirmPlannedOrder.Status);
        ProdOrderLine.SetRange("Prod. Order No.", FirmPlannedOrder."No.");
        ProdOrderLine.FindFirst();
        LibraryManufacturing.CreateProductionOrderComponent(ProdOrderComponent, FirmPlannedOrder.Status, FirmPlannedOrder."No.", ProdOrderLine."Line No.");
        ProdOrderComponent.Validate("Item No.", ComponentItem."No.");
        ProdOrderComponent.Validate("Quantity per", 1);
        ProdOrderComponent.Validate("Location Code", LocationCode);
        ProdOrderComponent.Modify(true);
        if not Release then begin
            ProductionOrder := FirmPlannedOrder;
            ProductionOrder.Find();
            exit;
        end;
        LibraryManufacturing.ChangeProdOrderStatus(FirmPlannedOrder, FirmPlannedOrder.Status::Released, WorkDate(), false);
        ProductionOrder.SetRange(Status, ProductionOrder.Status::Released);
        ProductionOrder.SetRange("Source No.", ParentItem."No.");
        ProductionOrder.FindLast();
    end;

    local procedure PrepareAssemblyOrder(var AssemblyHeader: Record "Assembly Header"; var ComponentItem: Record Item)
    var
        Location: Record Location;
        ParentItem: Record Item;
        AssemblyLine: Record "Assembly Line";
        ReleaseAssemblyDoc: Codeunit "Release Assembly Document";
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, true, false, true);
        Location.Validate("Asm. Consump. Whse. Handling", Location."Asm. Consump. Whse. Handling"::"Warehouse Pick (mandatory)");
        Location.Modify(true);
        Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(ComponentItem);
        Helper.CreatePositiveAdjustment(ComponentItem."No.", Location.Code, 5);
        LibraryInventory.CreateItem(ParentItem);
        LibraryAssembly.CreateAssemblyHeader(AssemblyHeader, WorkDate() + 1, ParentItem."No.", Location.Code, 1, '');
        LibraryAssembly.CreateAssemblyLine(AssemblyHeader, AssemblyLine, "BOM Component Type"::Item, ComponentItem."No.", ComponentItem."Base Unit of Measure", 2, 2, '');
        AssemblyLine.Validate("Location Code", Location.Code);
        AssemblyLine.Modify(true);
        ReleaseAssemblyDoc.Run(AssemblyHeader);
        AssemblyHeader.Get(AssemblyHeader."Document Type", AssemblyHeader."No.");
    end;

    local procedure PrepareProject(var Job: Record Job; var ComponentItem: Record Item)
    var
        Location: Record Location;
        JobTask: Record "Job Task";
        JobPlanningLine: Record "Job Planning Line";
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, true, false, true);
        Location.Validate("Job Consump. Whse. Handling", Location."Job Consump. Whse. Handling"::"Warehouse Pick (mandatory)");
        Location.Modify(true);
        Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(ComponentItem);
        Helper.CreatePositiveAdjustment(ComponentItem."No.", Location.Code, 5);
        LibraryJob.CreateJob(Job);
        Job.Validate(Status, Job.Status::Open);
        Job.Modify(true);
        LibraryJob.CreateJobTask(Job, JobTask);
        LibraryJob.CreateJobPlanningLine(JobTask, "Job Planning Line Line Type"::Budget, "Job Planning Line Type"::Item, ComponentItem."No.", 2, JobPlanningLine);
        JobPlanningLine.Validate("Location Code", Location.Code);
        JobPlanningLine.Modify(true);
        Job.Get(Job."No.");
    end;

    local procedure SourceRequest(SourceType: Text; SourceNo: Text): Text
    begin
        exit('{"sourceType":"' + SourceType + '","sourceNo":"' + SourceNo + '"}');
    end;

    local procedure CountPicks(SourceNo: Code[20]): Integer
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Picks: List of [Code[20]];
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("Whse. Document Type", ActivityLine."Whse. Document Type"::Production);
        ActivityLine.SetRange("Whse. Document No.", SourceNo);
        if ActivityLine.FindSet() then
            repeat
                if not Picks.Contains(ActivityLine."No.") then
                    if ActivityHeader.Get(ActivityHeader.Type::Pick, ActivityLine."No.") then
                        Picks.Add(ActivityLine."No.");
            until ActivityLine.Next() = 0;
        exit(Picks.Count());
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Clear(ResponseJson);
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
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
