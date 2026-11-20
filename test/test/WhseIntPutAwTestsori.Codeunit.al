namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InternalDocument;
using Microsoft.Warehouse.Ledger;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InternalPutaway.Create (#106) through the public dispatcher, its refusals, the Data.Records.Set closure and the permission denial.
/// </summary>
codeunit 97098 "Whse IntPutAw Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>AC01: stock in a bin becomes a released internal put-away and a put-away that registers into a pick bin.</summary>
    [Test]
    procedure Create_WithActivity_PutAwayRegistersIntoPickBin()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ActivityLine: Record "Warehouse Activity Line";
        BinContent: Record "Bin Content";
        ResponseJson: JsonObject;
        RegisterJson: JsonObject;
        ActivityNo: Code[20];
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 5);

        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":5}],"createActivity":true}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Released', TextValue(ResponseJson, 'documentStatus'), 'The internal put-away should be released.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'lineCount'), 'One internal put-away line.');
        Assert.AreEqual('Put-away', TextValue(ResponseJson, 'activityType'), 'A put-away should be created.');
        ActivityNo := CopyStr(TextValue(ResponseJson, 'activityNo'), 1, MaxStrLen(ActivityNo));
        Assert.AreNotEqual('', ActivityNo, 'The put-away number should be returned.');
        Assert.IsTrue(IntegerValue(ResponseJson, 'totalLines') >= 2, 'A take and a place line are expected.');

        Assert.IsTrue(RunType(Enum::"Message Type ori"::"Warehouse.Putaway.Register", ActivityNo, '{"expectedCount":1}', RegisterJson), 'The register response should be JSON.');
        Assert.AreEqual('Success', TextValue(RegisterJson, 'status'), ResponseText(RegisterJson));
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", ActivityNo);
        Assert.IsTrue(ActivityLine.IsEmpty(), 'The registered put-away should be gone.');
BinContent.SetRange("Location Code", Location.Code);
        BinContent.SetRange("Item No.", Item."No.");
        BinContent.SetFilter("Bin Code", '<>%1', ReceiveBin.Code);
        BinContent.SetAutoCalcFields(Quantity);
        BinContent.SetFilter(Quantity, '>0');
        Assert.IsFalse(BinContent.IsEmpty(), 'The stock should now be in the bin Business Central chose.');
        BinContent.SetRange("Bin Code", ReceiveBin.Code);
        Assert.IsTrue(BinContent.IsEmpty(), 'The from-bin should be empty.');
    end;

    /// <summary>AC02: getBinContent fills the lines from the bin content, the same as Get Bin Content in Business Central.</summary>
    [Test]
    procedure Create_GetBinContent_FillsLinesFromBin()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 3);

        Run('{"locationCode":"' + Location.Code + '","getBinContent":{"binCode":"' + ReceiveBin.Code + '","itemNo":"' + Item."No." + '"},"release":false}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Open', TextValue(ResponseJson, 'documentStatus'), 'release false leaves the document open.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'lineCount'), 'One bin content line.');
        LineJson := FirstLine(ResponseJson);
        Assert.AreEqual(Item."No.", TextValue(LineJson, 'itemNo'), 'Item from the bin content.');
        Assert.AreEqual(ReceiveBin.Code, TextValue(LineJson, 'fromBinCode'), 'From-bin from the bin content.');
        Assert.AreEqual(3, DecimalValue(LineJson, 'quantity'), 'The whole bin quantity.');
    end;

    /// <summary>AC04: a basic location is refused with PreconditionFailed and the inventory-movement next step.</summary>
    [Test]
    procedure Create_BasicLocation_IsRefused()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        Run('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"X","quantity":1,"fromBinCode":"B"}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Use Warehouse.InventoryMovement.Create for basic warehouse locations.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: more than the bin holds is refused with PreconditionFailed and nothing is written.</summary>
    [Test]
    procedure Create_InsufficientBinQuantity_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 2);
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":3}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Read Warehouse.BinContent.Get for the bin and lower the quantity.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: lines that together ask a bin for more than it holds are refused with PreconditionFailed and nothing is written.</summary>
    [Test]
    procedure Create_RepeatedLinesOverBinQuantity_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 5);
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":3},{"itemNo":"' + Item."No." + '","quantity":3}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Read Warehouse.BinContent.Get for the bin and lower the quantity.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: a lot-only line and a package-only line that draw on the same stock are refused together, and nothing is written.</summary>
    [Test]
    procedure Create_OverlappingTrackingLines_AreRefusedTogether()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 10);
        ReplaceBinStockByTrackedStock(ReceiveBin, Item, 10);
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":4,"lotNo":"LOT-A"},{"itemNo":"' + Item."No." + '","quantity":4,"packageNo":"PACK-P"}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Read Warehouse.BinContent.Get for the bin and lower the quantity.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: a lot that is not in the bin is refused like a short quantity.</summary>
    [Test]
    procedure Create_UnknownLotInBin_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 2);
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1,"lotNo":"NOLOT"}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Read Warehouse.BinContent.Get for the bin and lower the quantity.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: a from-bin blocked for all movement is refused with PreconditionFailed.</summary>
    [Test]
    procedure Create_BlockedBin_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 2);
        ReceiveBin.Get(ReceiveBin."Location Code", ReceiveBin.Code);
        ReceiveBin."Block Movement" := ReceiveBin."Block Movement"::All;
        ReceiveBin.Modify();
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Read the returned text, correct the bin, the bin content or the quantity, and send the request again. Nothing was written.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: missing, malformed, unknown, not found and conflicting input each answer their code with a next step.</summary>
    [Test]
    procedure Create_InvalidInput_EachCodeHasNextStep()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiveBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PrepareReceiveBinStock(Location, Item, ReceiveBin, 1);
        Run('{"lines":[]}', ResponseJson);
        AssertRefused(ResponseJson, 'MissingParameter', 'Send locationCode of a location with directed put-away and pick.');
        Run('{"locationCode":5}', ResponseJson);
        AssertRefused(ResponseJson, 'InvalidParameterFormat', '');
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1}],"colour":"red"}', ResponseJson);
        AssertRefused(ResponseJson, 'UnknownParameter', 'Remove this key or consult Help.Implementation.Get for the declared parameters.');
        Run('{"locationCode":"NOSUCHLOC"}', ResponseJson);
        AssertRefused(ResponseJson, 'RecordNotFound', 'Check the code with Warehouse.BinContent.Get or Warehouse.Bin.Get.');
        RunWithSubject('{"locationCode":"' + Location.Code + '"}', 'OTHERLOC', ResponseJson);
        AssertRefused(ResponseJson, 'ConflictingIdentifiers', 'Send one location: subject or locationCode.');
        Run('{"locationCode":"' + Location.Code + '","fromBinCode":"' + ReceiveBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":0}]}', ResponseJson);
        AssertRefused(ResponseJson, 'InvalidParameter', 'Send a quantity greater than zero.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC05: Data.Records.Set on the internal put-away tables is refused and names the new type.</summary>
    [Test]
    procedure GenericWrite_InternalTables_IsRefusedAndHinted()
    var
        TempArgument: Record "Message Argument ori" temporary;
    begin
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Whse. Internal Put-away Header", false), 'Put-away header closed.');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Whse. Internal Put-away Line", false), 'Put-away line closed.');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Whse. Internal Pick Header", false), 'Pick header closed.');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Whse. Internal Pick Line", false), 'Pick line closed.');
        Assert.AreEqual('Warehouse.InternalPutaway.Create', TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Whse. Internal Put-away Header"), 'Put-away header hint.');
        Assert.AreEqual('Warehouse.InternalPutaway.Create', TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Whse. Internal Put-away Line"), 'Put-away line hint.');
        Assert.AreEqual('Warehouse.InternalPick.Create', TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Whse. Internal Pick Header"), 'Pick header hint.');
        Assert.AreEqual('Warehouse.InternalPick.Create', TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Whse. Internal Pick Line"), 'Pick line hint.');
    end;

    /// <summary>AC06: discovery text is English in 1033 and Icelandic in 1039.</summary>
    [Test]
    procedure Help_DiscoveryText_IsTranslated()
    var
        Discovery: Interface "Msg Discovery ori";
        PreviousLanguage: Integer;
        EnglishText: Text;
    begin
        Discovery := Enum::"Message Type ori"::"Warehouse.InternalPutaway.Create";
        PreviousLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        EnglishText := Discovery.GetSelectionDescription();
        Assert.IsTrue(EnglishText.StartsWith('Creates and releases an internal put-away'), EnglishText);
        GlobalLanguage(1039);
        Assert.IsTrue(Discovery.GetSelectionDescription().StartsWith('Stofnar og gefur út innri frágang'), Discovery.GetSelectionDescription());
        GlobalLanguage(PreviousLanguage);
    end;

    /// <summary>AC06: without write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CreateImpl: Codeunit "Whse IntPutAw Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InternalPutaway.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure EnsureInternalDocumentNos()
    var
        WarehouseSetup: Record "Warehouse Setup";
        LibraryUtility: Codeunit "Library - Utility";
    begin
        // A fresh CRONUS company has no internal pick and put-away number series; Business Central needs them to insert the documents.
        WarehouseSetup.Get();
        if WarehouseSetup."Whse. Internal Pick Nos." = '' then
            WarehouseSetup.Validate("Whse. Internal Pick Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        if WarehouseSetup."Whse. Internal Put-away Nos." = '' then
            WarehouseSetup.Validate("Whse. Internal Put-away Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        WarehouseSetup.Modify(true);
    end;

    local procedure PrepareReceiveBinStock(var Location: Record Location; var Item: Record Item; var ReceiveBin: Record Bin; Quantity: Decimal)
    var
        Zone: Record Zone;
    begin
        EnsureInternalDocumentNos();
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        EnsureDefaultDirectedEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        // Business Central refuses a receive bin as the from-bin of an internal put-away, so the stock sits in a put-away and pick bin.
        LibraryWarehouse.FindZone(Zone, Location.Code, LibraryWarehouse.SelectBinType(false, false, true, true), false);
        LibraryWarehouse.FindBin(ReceiveBin, Location.Code, Zone.Code, 1);
        LibraryWarehouse.UpdateWarehouseStockOnBin(ReceiveBin, Item."No.", Quantity, false);
    end;

    local procedure ReplaceBinStockByTrackedStock(Bin: Record Bin; Item: Record Item; UntrackedQuantity: Decimal)
    begin
        // Offsets the untracked stock and books 5 units in LOT-A/PACK-P and 5 in LOT-B/PACK-Q, so only 5 units can satisfy a lot-only and a package-only line together.
        InsertWarehouseEntry(Bin, Item, -UntrackedQuantity, '', '');
        InsertWarehouseEntry(Bin, Item, 5, 'LOT-A', 'PACK-P');
        InsertWarehouseEntry(Bin, Item, 5, 'LOT-B', 'PACK-Q');
    end;

    local procedure InsertWarehouseEntry(Bin: Record Bin; Item: Record Item; Quantity: Decimal; LotNo: Code[50]; PackageNo: Code[50])
    var
        WarehouseEntry: Record "Warehouse Entry";
        LastEntry: Record "Warehouse Entry";
    begin
        // Entry numbers come from a sequence that this insert must not consume, so the fixture takes numbers far above it; the test run rolls them back.
        LastEntry.SetLoadFields("Entry No.");
        if LastEntry.FindLast() then
            WarehouseEntry."Entry No." := LastEntry."Entry No." + 1000000
        else
            WarehouseEntry."Entry No." := 1000000;
        WarehouseEntry."Location Code" := Bin."Location Code";
        WarehouseEntry."Zone Code" := Bin."Zone Code";
        WarehouseEntry."Bin Code" := Bin.Code;
        WarehouseEntry."Item No." := Item."No.";
        WarehouseEntry."Unit of Measure Code" := Item."Base Unit of Measure";
        WarehouseEntry."Qty. per Unit of Measure" := 1;
        WarehouseEntry.Quantity := Quantity;
        WarehouseEntry."Qty. (Base)" := Quantity;
        WarehouseEntry."Lot No." := LotNo;
        WarehouseEntry."Package No." := PackageNo;
        WarehouseEntry."Registering Date" := WorkDate();
        WarehouseEntry.Insert();
    end;

    local procedure EnsureDefaultDirectedEmployee(LocationCode: Code[10])
    var
        WarehouseEmployee: Record "Warehouse Employee";
        Existing: Record "Warehouse Employee";
        UserCode: Code[50];
    begin
        UserCode := CopyStr(UserId(), 1, MaxStrLen(UserCode));
        if UserCode = '' then
            exit;
        Existing.SetRange("User ID", UserCode);
        Existing.SetRange(Default, true);
        Existing.SetFilter("Location Code", '<>%1', LocationCode);
        Existing.ModifyAll(Default, false);
        if WarehouseEmployee.Get(UserCode, LocationCode) then begin
            WarehouseEmployee.Default := true;
            WarehouseEmployee.Modify(true);
            exit;
        end;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := true;
        WarehouseEmployee.Insert(true);
    end;

    local procedure AssertRefused(ResponseJson: JsonObject; ExpectedCode: Text; ExpectedNextStep: Text)
    begin
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsTrue(StrPos(ResponseText(ResponseJson), '"' + ExpectedCode + '"') > 0, 'Expected ' + ExpectedCode + ': ' + ResponseText(ResponseJson));
        if ExpectedNextStep <> '' then
            Assert.IsTrue(StrPos(ResponseText(ResponseJson), ExpectedNextStep) > 0, 'Expected next step ' + ExpectedNextStep + ': ' + ResponseText(ResponseJson));
        Assert.IsTrue(StrPos(ResponseText(ResponseJson), 'nextStep') > 0, 'Every refusal carries a nextStep: ' + ResponseText(ResponseJson));
    end;

    local procedure AssertNothingWritten(LocationCode: Code[10])
    var
        Header: Record "Whse. Internal Put-away Header";
    begin
        Header.SetRange("Location Code", LocationCode);
        Assert.IsTrue(Header.IsEmpty(), 'A refusal must not leave an internal put-away.');
    end;

    local procedure Run(RequestText: Text; var ResponseJson: JsonObject)
    begin
        RunWithSubject(RequestText, '', ResponseJson);
    end;

    local procedure RunWithSubject(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(RunType(Enum::"Message Type ori"::"Warehouse.InternalPutaway.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure RunType(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Clear(ResponseJson);
        exit(Helper.RunMessage(MessageType, Subject, RequestText, ResponseJson));
    end;

    local procedure FirstLine(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(ResponseJson.Get('lines', Token), 'The response should list lines.');
        Token.AsArray().Get(0, Token);
        exit(Token.AsObject());
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

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        exit(Token.AsValue().AsDecimal());
    end;
}
