namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.BinReplenishment.Calculate through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97091 "Whse Bin Repl Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>A fixed pick bin below its minimum gets one movement worksheet line from the bulk bin.</summary>
    [Test]
    procedure Calculate_BelowMinimum_CreatesWorksheetLine()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        WorksheetName: Record "Whse. Worksheet Name";
        ResponseJson: JsonObject;
        Line: JsonObject;
    begin
        PrepareReplenishment(Location, Item, FromBin, ToBin, WorksheetName);

        Run(RequestText(Location.Code, WorksheetName."Worksheet Template Name", WorksheetName.Name, false), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(Location.Code, TextValue(ResponseJson, 'locationCode'), 'The location should be returned.');
        Assert.IsTrue(IntegerValue(ResponseJson, 'lineCount') >= 1, ResponseText(ResponseJson));
        Line := FirstLine(ResponseJson);
        Assert.AreEqual(Item."No.", TextValue(Line, 'itemNo'), 'The item should be returned.');
        Assert.AreEqual(FromBin.Code, TextValue(Line, 'fromBin'), 'The bulk bin should be the from-bin.');
        Assert.AreEqual(ToBin.Code, TextValue(Line, 'toBin'), 'The pick bin should be the to-bin.');
        Assert.IsTrue(DecimalValue(Line, 'quantity') > 0, 'The replenishment quantity should be greater than zero.');
    end;

    /// <summary>A location without directed put-away and pick is refused and writes nothing.</summary>
    [Test]
    procedure Calculate_LocationNotDirected_IsRefused()
    var
        Location: Record Location;
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run(RequestText(Location.Code, 'MOVEMENT', 'DEFAULT', false), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Bin replenishment needs a directed location.', TextValue(ResponseJson, 'nextStep'), 'The next step should say a directed location is required.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'A location that is not directed must not get worksheet lines.');
    end;

    /// <summary>A missing worksheet template or name is refused and writes nothing.</summary>
    [Test]
    procedure Calculate_MissingWorksheetName_IsRefused()
    var
        Location: Record Location;
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 1);
        EnsureDefaultDirectedEmployee(Location.Code);

        Run(RequestText(Location.Code, 'NOTEMPLATE', 'NONAME', false), '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Create the movement worksheet name first.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to create the worksheet name.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'A missing worksheet must not get lines.');
    end;

    /// <summary>A request without worksheetName is refused.</summary>
    [Test]
    procedure Calculate_MissingKeys_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"locationCode":"WHITE","worksheetTemplateName":"MOVEMENT"}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('worksheetName', TextValue(ResponseJson, 'parameter'), 'The error should name worksheetName.');
        Assert.AreEqual('Send locationCode, worksheetTemplateName and worksheetName.', TextValue(ResponseJson, 'nextStep'), 'The next step should name the required keys.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Calculate_UnknownKey_IsRefused()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        PrepareEmptyWorksheet(Location, WorksheetName);

        Run('{"note":"nope",' + CopyStr(RequestText(Location.Code, WorksheetName."Worksheet Template Name", WorksheetName.Name, false), 2), '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'An unknown key must not write worksheet lines.');
    end;

    /// <summary>A boolean sent as text is refused.</summary>
    [Test]
    procedure Calculate_WrongBooleanType_IsRefused()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        ResponseJson: JsonObject;
    begin
        PrepareEmptyWorksheet(Location, WorksheetName);

        Run(RequestText(Location.Code, WorksheetName."Worksheet Template Name", WorksheetName.Name, false).Replace('"autoCreateMovement":false', '"doNotFillQtyToHandle":"yes"'), '', ResponseJson);

        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('doNotFillQtyToHandle', TextValue(ResponseJson, 'parameter'), 'The error should name the boolean.');
        Assert.AreEqual('Send true or false.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to send true or false.');
    end;

    /// <summary>subject and locationCode that name different locations are refused.</summary>
    [Test]
    procedure Calculate_ConflictingLocation_IsRefused()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        PrepareEmptyWorksheet(Location, WorksheetName);

        Run(RequestText(Location.Code, WorksheetName."Worksheet Template Name", WorksheetName.Name, false), 'OTHER', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send one location: subject or locationCode.', TextValue(ResponseJson, 'nextStep'), 'The next step should say to send one location.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'A conflict must not write worksheet lines.');
    end;

    /// <summary>Nothing to replenish is a success with an empty line list.</summary>
    [Test]
    procedure Calculate_NothingToReplenish_ReturnsEmptyLines()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        PrepareEmptyWorksheet(Location, WorksheetName);

        Run(RequestText(Location.Code, WorksheetName."Worksheet Template Name", WorksheetName.Name, false), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'lineCount'), 'An empty replenishment should return no lines.');
        Assert.IsTrue(ResponseJson.Get('lines', Token), 'The response should include lines.');
        Assert.AreEqual(0, Token.AsArray().Count(), 'The line list should be empty.');
    end;

    /// <summary>autoCreateMovement true is refused because this type does not create the movement.</summary>
    [Test]
    procedure Calculate_AutoCreateMovement_IsRefused()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        PrepareEmptyWorksheet(Location, WorksheetName);

        Run(RequestText(Location.Code, WorksheetName."Worksheet Template Name", WorksheetName.Name, true), '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use Warehouse.Movement.Create after the worksheet lines exist.', TextValue(ResponseJson, 'nextStep'), 'The next step should name Warehouse.Movement.Create.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'autoCreateMovement must not write worksheet lines.');
    end;

    /// <summary>Calculate is disabled and returns PermissionDenied without write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Calculate_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        CalculateImpl: Codeunit "Whse Bin Repl Calc Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.BinReplenishment.Calculate";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Calculate must be disabled without write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CalculateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure PrepareReplenishment(var Location: Record Location; var Item: Record Item; var FromBin: Record Bin; var ToBin: Record Bin; var WorksheetName: Record "Whse. Worksheet Name")
    var
        ToContent: Record "Bin Content";
    begin
        PrepareEmptyWorksheet(Location, WorksheetName);
        LibraryWarehouse.FindBin(FromBin, Location.Code, 'BULK', 1);
        LibraryWarehouse.FindBin(ToBin, Location.Code, 'PICK', 1);
        FromBin.Validate("Bin Ranking", 10);
        FromBin.Modify(true);
        ToBin.Validate("Bin Ranking", 100);
        ToBin.Modify(true);
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.UpdateWarehouseStockOnBin(FromBin, Item."No.", 8, false);
        LibraryWarehouse.CreateBinContent(ToContent, Location.Code, 'PICK', ToBin.Code, Item."No.", '', Item."Base Unit of Measure");
        ToContent.Validate(Fixed, true);
        ToContent.Validate("Min. Qty.", 4);
        ToContent.Validate("Max. Qty.", 8);
        // Bin Code validation copies ranking only when CurrFieldNo is set. Assign the pick ranking explicitly.
        ToContent."Bin Ranking" := 100;
        ToContent.Modify(true);
        AssertReplenishmentSetup(Location.Code, Item."No.");
    end;

    local procedure AssertReplenishmentSetup(LocationCode: Code[10]; ItemNo: Code[20])
    var
        FromContent: Record "Bin Content";
        ToContent: Record "Bin Content";
    begin
        ToContent.SetRange("Location Code", LocationCode);
        ToContent.SetRange("Item No.", ItemNo);
        ToContent.SetRange(Fixed, true);
        Assert.AreEqual(1, ToContent.Count(), 'The pick bin should have one fixed bin content.');
        ToContent.FindFirst();
        ToContent.CalcFields("Quantity (Base)");
        FromContent.SetRange("Location Code", LocationCode);
        FromContent.SetRange("Item No.", ItemNo);
        FromContent.SetRange(Fixed, false);
        Assert.AreEqual(1, FromContent.Count(), 'The bulk bin should have one bin content.');
        FromContent.FindFirst();
        FromContent.CalcFields("Quantity (Base)");
        Assert.AreEqual(0, ToContent."Quantity (Base)", 'The pick bin should be empty.');
        Assert.IsTrue(FromContent."Quantity (Base)" > 0, 'The bulk bin should contain the item.');
        Assert.IsTrue(FromContent."Bin Ranking" < ToContent."Bin Ranking", RankingText(FromContent."Bin Ranking", ToContent."Bin Ranking"));
        Assert.AreEqual(ToContent."Unit of Measure Code", FromContent."Unit of Measure Code", 'The units of measure should match.');
        Assert.AreEqual(ToContent."Qty. per Unit of Measure", FromContent."Qty. per Unit of Measure", 'The quantity per unit should match.');
        Assert.IsTrue(ToContent."Qty. per Unit of Measure" > 0, 'The quantity per unit should be greater than zero.');
    end;

    local procedure RankingText(FromRanking: Integer; ToRanking: Integer): Text
    var
        RankingLbl: Label 'Rankings from %1 to %2.', Comment = '%1 = from ranking, %2 = to ranking, is-IS=Röðun frá %1 til %2.';
    begin
        exit(StrSubstNo(RankingLbl, FromRanking, ToRanking));
    end;

    local procedure PrepareEmptyWorksheet(var Location: Record Location; var WorksheetName: Record "Whse. Worksheet Name")
    var
        TemplateName: Code[10];
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        EnsureDefaultDirectedEmployee(Location.Code);
        TemplateName := EnsureMovementWorksheetTemplate();
        LibraryWarehouse.CreateWhseWorksheetName(WorksheetName, TemplateName, Location.Code);
    end;

    local procedure EnsureMovementWorksheetTemplate(): Code[10]
    var
        WorksheetTemplate: Record "Whse. Worksheet Template";
    begin
        WorksheetTemplate.SetRange(Type, WorksheetTemplate.Type::Movement);
        if WorksheetTemplate.FindFirst() then
            exit(WorksheetTemplate.Name);
        WorksheetTemplate.Init();
        WorksheetTemplate.Name := 'MOVEMENT';
        WorksheetTemplate.Validate(Type, WorksheetTemplate.Type::Movement);
        WorksheetTemplate.Description := 'Movement';
        WorksheetTemplate.Insert(true);
        exit(WorksheetTemplate.Name);
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
        while Existing.FindFirst() do begin
            Existing.Default := false;
            Existing.Modify(true);
        end;
        if WarehouseEmployee.Get(UserCode, LocationCode) then begin
            if not WarehouseEmployee.Default then begin
                WarehouseEmployee.Default := true;
                WarehouseEmployee.Modify(true);
            end;
            exit;
        end;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := true;
        WarehouseEmployee.Insert(true);
    end;

    local procedure RequestText(LocationCode: Code[10]; TemplateName: Code[10]; WorksheetName: Code[10]; AutoCreateMovement: Boolean): Text
    var
        AutoText: Text;
    begin
        if AutoCreateMovement then
            AutoText := 'true'
        else
            AutoText := 'false';
        exit('{"locationCode":"' + LocationCode + '","worksheetTemplateName":"' + TemplateName + '","worksheetName":"' + WorksheetName + '","autoCreateMovement":' + AutoText + '}');
    end;

    local procedure Run(BodyText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.BinReplenishment.Calculate", Subject, BodyText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstLine(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Lines: JsonArray;
    begin
        Assert.IsTrue(ResponseJson.Get('lines', Token), 'The response should list lines.');
        Lines := Token.AsArray();
        Lines.Get(0, Token);
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
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;
}
