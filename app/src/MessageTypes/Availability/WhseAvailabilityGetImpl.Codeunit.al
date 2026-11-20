namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Tracking;
using Microsoft.Warehouse.Availability;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Ledger;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Tracking;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Availability.Get: how much of an item Business Central lets a user pick at a location,
/// per bin and per lot, serial or package. Every number comes from Business Central's own calculations.
/// </summary>
codeunit 10078440 "Whse Availability Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    var
        TempTrackingSetup: Record "Item Tracking Setup" temporary;
        TempWhseItemTrackingLine: Record "Whse. Item Tracking Line" temporary;
        HasTrackingFilter: Boolean;

    /// <summary>Returns whether the caller can read Bin Content.</summary>
    /// <returns>True when the caller has read permission on Bin Content.</returns>
    procedure IsEnabled(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(GetFilterTableNo());
        exit(RecRef.ReadPermission());
    end;

    /// <summary>Returns the table used to evaluate caller read permission.</summary>
    /// <returns>The Bin Content table ID.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Bin Content");
    end;

    /// <summary>Returns a short description of Warehouse.Availability.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reads how much of an item can be picked at a location, per bin and per lot, serial or package.', Comment = 'is-IS=Les hversu mikið af vöru er hægt að tína á staðsetningu, eftir hólfum og eftir lotu, raðnúmeri eða pakka.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'available to pick, pick availability, why is the pick short, bin availability, lot availability, stock on pick, blocked bin, dedicated bin', Comment = 'is-IS=tiltækt til tínslu, tínsluframboð, af hverju er tínslan of lítil, framboð í hólfum, framboð eftir lotu, birgðir á tínslu, læst hólf, hólf með sérstakt hlutverk';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Shows how much of one item can be picked at one location and why the rest cannot. Use Inventory.AvailableToPromise.Get for availability to promise.', Comment = 'is-IS=Lesaðgangur. Sýnir hversu mikið af einni vöru er hægt að tína á einni staðsetningu og hvers vegna afgangurinn er ekki tiltækur. Notaðu Inventory.AvailableToPromise.Get fyrir loforðsframboð.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('filter only');
        Envelope := Parts.RecordEnvelope(Forms, 'No single record is required; locationCode and itemNo under data select what is read.', true);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('data.locationCode, data.itemNo', 'location code and item number', 'The location and the item whose pick availability is read.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Location code.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', true, 'Item number.'));
        Parameters.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Item variant code. Blank reads the item without a variant.'));
        Parameters.Add(ContractMgt.Parameter('unitOfMeasureCode', 'string', false, 'Unit of measure the quantities are returned in. Default: the base unit of measure of the item.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Narrows bins and tracking to one bin.'));
        Parameters.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Narrows bins and tracking to one zone.'));
        Parameters.Add(ContractMgt.Parameter('lotNo', 'string', false, 'Reads availability of one lot.'));
        Parameters.Add(ContractMgt.Parameter('serialNo', 'string', false, 'Reads availability of one serial number.'));
        Parameters.Add(ContractMgt.Parameter('packageNo', 'string', false, 'Reads availability of one package number.'));
        Parameters.Add(ContractMgt.Parameter('includeBins', 'boolean', false, 'True adds the bins list. Default false.'));
        Parameters.Add(ContractMgt.Parameter('includeTracking', 'boolean', false, 'True adds the tracking list, one row per lot, serial and package. Default false.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        BinFields: JsonArray;
        TrackingFields: JsonArray;
        BinsField: JsonObject;
        TrackingField: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        Fields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        Fields.Add(ContractMgt.ResponseField('baseUnitOfMeasure', 'string', 'Base unit of measure of the item.'));
        Fields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure the quantities are in.'));
        Fields.Add(ContractMgt.ResponseField('qtyInWarehouse', 'number', 'Quantity of the item in the location.'));
        Fields.Add(ContractMgt.ResponseField('qtyOnPicks', 'number', 'Quantity already assigned to open picks and other open warehouse activities.'));
        Fields.Add(ContractMgt.ResponseField('qtyOnDedicatedBins', 'number', 'Quantity in dedicated bins, which cannot be picked for other documents.'));
        Fields.Add(ContractMgt.ResponseField('qtyOnBlockedBins', 'number', 'Quantity in bins that are blocked for outbound movement, and blocked lots, serial or package numbers.'));
        Fields.Add(ContractMgt.ResponseField('qtyReservedOnInventory', 'number', 'Quantity of inventory that is reserved.'));
        Fields.Add(ContractMgt.ResponseField('qtyInReceiveShipQcBins', 'number', 'Quantity in the receipt, shipment, adjustment and production bins of the location, which are not picked from.'));
        Fields.Add(ContractMgt.ResponseField('qtyAvailableToPick', 'number', 'Quantity Business Central lets a pick take now.'));
        Fields.Add(ContractMgt.ResponseField('note', 'string', 'Present when the location has no bins: the quantities are inventory quantities.'));
        BinFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin code.'));
        BinFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone code.'));
        BinFields.Add(ContractMgt.ResponseField('binTypeCode', 'string', 'Bin type code.'));
        BinFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity in the bin.'));
        BinFields.Add(ContractMgt.ResponseField('qtyAvailableToTake', 'number', 'Quantity that can be taken from the bin.'));
        BinFields.Add(ContractMgt.ResponseField('pickQty', 'number', 'Quantity assigned to open picks from the bin.'));
        BinFields.Add(ContractMgt.ResponseField('blockMovement', 'string', 'Inbound, Outbound or All when movement is blocked; otherwise blank.'));
        BinFields.Add(ContractMgt.ResponseField('dedicated', 'boolean', 'Whether the bin is dedicated.'));
        BinsField.Add('name', 'bins');
        BinsField.Add('type', 'array');
        BinsField.Add('description', 'One row per bin with the item. Only with includeBins.');
        BinsField.Add('children', BinFields);
        Fields.Add(BinsField);
        TrackingFields.Add(ContractMgt.ResponseField('lotNo', 'string', 'Lot number.'));
        TrackingFields.Add(ContractMgt.ResponseField('serialNo', 'string', 'Serial number.'));
        TrackingFields.Add(ContractMgt.ResponseField('packageNo', 'string', 'Package number.'));
        TrackingFields.Add(ContractMgt.ResponseField('expirationDate', 'string', 'Expiration date as YYYY-MM-DD, or blank.'));
        TrackingFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity with this tracking in the location.'));
        TrackingFields.Add(ContractMgt.ResponseField('qtyAvailableToPick', 'number', 'Quantity of this lot, serial or package Business Central lets a pick take now.'));
        TrackingField.Add('name', 'tracking');
        TrackingField.Add('type', 'array');
        TrackingField.Add('description', 'One row per lot, serial and package that is not blocked. Only with includeTracking.');
        TrackingField.Add('children', TrackingFields);
        Fields.Add(TrackingField);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        MissingWhenLbl: Label 'locationCode or itemNo was not sent.', Comment = 'is-IS=locationCode eða itemNo var ekki sent.';
        MissingNextStepLbl: Label 'Send locationCode and itemNo.', Comment = 'is-IS=Sendu locationCode og itemNo.';
        FormatWhenLbl: Label 'A code was not text, or includeBins or includeTracking was not true or false.', Comment = 'is-IS=Kóði var ekki texti, eða includeBins eða includeTracking var ekki true eða false.';
        FormatNextStepLbl: Label 'Send text for codes and true or false for includeBins and includeTracking.', Comment = 'is-IS=Sendu texta fyrir kóða og true eða false fyrir includeBins og includeTracking.';
        UnknownWhenLbl: Label 'The request contains a key this type does not accept.', Comment = 'is-IS=Beiðnin inniheldur lykil sem þessi gerð tekur ekki við.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
        NotFoundWhenLbl: Label 'The location, item, variant, unit of measure, bin or zone does not exist.', Comment = 'is-IS=Staðsetningin, varan, afbrigðið, mælieiningin, hólfið eða svæðið er ekki til.';
        NotFoundNextStepLbl: Label 'Check the code named in the error and try again.', Comment = 'is-IS=Athugaðu kóðann sem villan nefnir og reyndu aftur.';
    begin
        Parts.AddNextStepError(Errors, "Bifrost Error Code ori"::MissingParameter, MissingWhenLbl, MissingNextStepLbl);
        Parts.AddNextStepError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, FormatWhenLbl, FormatNextStepLbl);
        Parts.AddNextStepError(Errors, "Bifrost Error Code ori"::UnknownParameter, UnknownWhenLbl, UnknownNextStepLbl);
        Parts.AddNextStepError(Errors, "Bifrost Error Code ori"::RecordNotFound, NotFoundWhenLbl, NotFoundNextStepLbl);
        Parts.AddPermissionError(Errors, 'BIFROST Whse - Read ori');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads stock, bins, picks and reservations and changes nothing.', 'BIFROST Read ori');
        exit(true);
    end;

    procedure GetMetering(var Metering: JsonObject): Boolean
    begin
        exit(false);
    end;

    procedure GetRelated(var Related: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'You want the raw quantity in each bin, without what is assigned or blocked.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Create', 'Create the pick once you know what is available.'));
        // Bifrost Inventory is not a dependency (#107, same rule as #68). Name its types only when that app is installed.
        AddInstalledRelated(Related, ContractMgt, 'Inventory.AvailableToPromise.Get', 'You want availability to promise at item and location level, not the warehouse view.');
        AddInstalledRelated(Related, ContractMgt, 'Inventory.AvailabilityByEvent.Get', 'You want the availability by supply and demand event.');
        AddInstalledRelated(Related, ContractMgt, 'Inventory.AvailabilityByPeriod.Get', 'You want the availability by period.');
        AddInstalledRelated(Related, ContractMgt, 'Inventory.TrackingAvailability.Get', 'You want lot and serial availability at item level.');
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.OutboundWorkflow(Workflow);
        exit(true);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Read what can be picked of one item',
            '{"locationCode":"SILVER","itemNo":"1896-S"}',
            '{"status":"Success","itemNo":"1896-S","variantCode":"","locationCode":"SILVER","baseUnitOfMeasure":"PCS","unitOfMeasureCode":"PCS","qtyInWarehouse":20,"qtyOnPicks":4,"qtyOnDedicatedBins":0,"qtyOnBlockedBins":6,"qtyReservedOnInventory":0,"qtyInReceiveShipQcBins":0,"qtyAvailableToPick":10}'));
        Examples.Add(ContractMgt.Example(
            'Read it per bin',
            '{"locationCode":"SILVER","itemNo":"1896-S","includeBins":true}',
            '{"status":"Success","itemNo":"1896-S","variantCode":"","locationCode":"SILVER","baseUnitOfMeasure":"PCS","unitOfMeasureCode":"PCS","qtyInWarehouse":10,"qtyOnPicks":0,"qtyOnDedicatedBins":0,"qtyOnBlockedBins":0,"qtyReservedOnInventory":0,"qtyInReceiveShipQcBins":0,"qtyAvailableToPick":10,"bins":[{"binCode":"S-01-0001","zoneCode":"PICK","binTypeCode":"PICK","quantity":10,"qtyAvailableToTake":10,"pickQty":0,"blockMovement":"","dedicated":false}]}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only. Shows how much of one item Business Central will let a pick take at a location, per bin and per lot, serial or package, and what keeps the rest from being picked.';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'locationCode and itemNo are required. All quantities are in the unit of measure of unitOfMeasureCode, by default the base unit of measure of the item. ' +
            'The totals are Business Central''s own calculations, so qtyAvailableToPick is what a pick can take now: stock that is on open picks, in dedicated bins, in blocked bins, reserved, or in receipt, shipment and production bins is not available, and blocked lots, serial numbers and packages are left out. ' +
            'The totals add up to qtyInWarehouse only roughly, because one quantity can be counted in more than one of them, for example a dedicated bin that is also blocked. ' +
            'includeBins adds one row per bin that holds the item; binCode and zoneCode narrow the list. includeTracking adds one row per lot, serial and package number that is not blocked, with the expiration date; lotNo, serialNo and packageNo narrow the list and the totals. ' +
            'A location without bins answers the inventory of the location with an empty bins list and a note. An item without stock is Success with zeros. ' +
            'A pick that created for a shipment can still take less when that shipment line has its own reservation. ' +
            'When Bifrost Inventory is installed, related also names Inventory.AvailableToPromise.Get, Inventory.AvailabilityByEvent.Get, Inventory.AvailabilityByPeriod.Get and Inventory.TrackingAvailability.Get. Those names are left out when that app is not installed.';
        exit(true);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Reads the availability of one item at one location.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        Location: Record Location;
        Item: Record Item;
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        LocationCode: Text;
        ItemNo: Text;
        VariantCode: Text;
        UnitOfMeasureCode: Text;
        BinCode: Text;
        ZoneCode: Text;
        LotNo: Text;
        SerialNo: Text;
        PackageNo: Text;
        IncludeBins: Boolean;
        IncludeTracking: Boolean;
        Present: Boolean;
        DeniedLbl: Label 'You do not have permission to read warehouse availability.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa framboð í vöruhúsi.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
        ProblemsLbl: Label 'The availability query was refused.', Comment = 'is-IS=Fyrirspurn um framboð var hafnað.';
    begin
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        RefuseUnknownKeys(RequestJson, Argument);
        Context.ReadText(RequestJson, 'locationCode', MaxStrLen(Location.Code), Argument, LocationCode, Present, 'locationCode');
        Context.ReadText(RequestJson, 'itemNo', MaxStrLen(Item."No."), Argument, ItemNo, Present, 'itemNo');
        Context.ReadText(RequestJson, 'variantCode', 10, Argument, VariantCode, Present, 'variantCode');
        Context.ReadText(RequestJson, 'unitOfMeasureCode', 10, Argument, UnitOfMeasureCode, Present, 'unitOfMeasureCode');
        Context.ReadText(RequestJson, 'binCode', 20, Argument, BinCode, Present, 'binCode');
        Context.ReadText(RequestJson, 'zoneCode', 10, Argument, ZoneCode, Present, 'zoneCode');
        Context.ReadText(RequestJson, 'lotNo', 50, Argument, LotNo, Present, 'lotNo');
        Context.ReadText(RequestJson, 'serialNo', 50, Argument, SerialNo, Present, 'serialNo');
        Context.ReadText(RequestJson, 'packageNo', 50, Argument, PackageNo, Present, 'packageNo');
        Context.ReadBoolean(RequestJson, 'includeBins', Argument, IncludeBins, Present, 'includeBins');
        Context.ReadBoolean(RequestJson, 'includeTracking', Argument, IncludeTracking, Present, 'includeTracking');
        CheckRequired(RequestJson, Argument, LocationCode, ItemNo);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not FindMasterData(Argument, Location, Item, LocationCode, ItemNo, VariantCode, UnitOfMeasureCode, BinCode, ZoneCode) then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        SetTracking(Item."No.", Location.Code, CopyStr(VariantCode, 1, 10), LotNo, SerialNo, PackageNo);
        WriteAvailability(Argument, Location, Item, CopyStr(VariantCode, 1, 10), CopyStr(UnitOfMeasureCode, 1, 10), CopyStr(BinCode, 1, 20), CopyStr(ZoneCode, 1, 10), LotNo, SerialNo, PackageNo, IncludeBins, IncludeTracking);
    end;

    local procedure CheckRequired(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; LocationCode: Text; ItemNo: Text)
    var
        LocationMissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        ItemMissingLbl: Label 'itemNo is required.', Comment = 'is-IS=itemNo er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode and itemNo.', Comment = 'is-IS=Sendu locationCode og itemNo.';
    begin
        if (LocationCode = '') and not IsBadValue(RequestJson, 'locationCode') then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, LocationMissingLbl, 'locationCode', '', '', MissingNextStepLbl);
        if (ItemNo = '') and not IsBadValue(RequestJson, 'itemNo') then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, ItemMissingLbl, 'itemNo', '', '', MissingNextStepLbl);
    end;

    local procedure IsBadValue(RequestJson: JsonObject; KeyName: Text): Boolean
    var
        Token: JsonToken;
    begin
        // A value of the wrong type or length has been answered under its own name already.
        if not RequestJson.Get(KeyName, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(true);
        if Token.AsValue().IsNull() then
            exit(false);
        exit(Token.AsValue().AsText() <> '');
    end;

    local procedure FindMasterData(var Argument: Record "Message Argument ori"; var Location: Record Location; var Item: Record Item; LocationCode: Text; ItemNo: Text; VariantCode: Text; var UnitOfMeasureCode: Text; BinCode: Text; ZoneCode: Text): Boolean
    var
        ItemVariant: Record "Item Variant";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        Bin: Record Bin;
        Zone: Record Zone;
        LocationMissingLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        ItemMissingLbl: Label 'Item %1 was not found.', Comment = '%1 = item number, is-IS=Vara %1 fannst ekki.';
        VariantMissingLbl: Label 'Variant %1 of item %2 was not found.', Comment = '%1 = variant code, %2 = item number, is-IS=Afbrigði %1 af vöru %2 fannst ekki.';
        UnitMissingLbl: Label 'Unit of measure %1 is not a unit of measure of item %2.', Comment = '%1 = unit of measure code, %2 = item number, is-IS=Mælieining %1 er ekki mælieining vöru %2.';
        BinMissingLbl: Label 'Bin %1 was not found at location %2.', Comment = '%1 = bin code, %2 = location code, is-IS=Hólf %1 fannst ekki á staðsetningu %2.';
        ZoneMissingLbl: Label 'Zone %1 was not found at location %2.', Comment = '%1 = zone code, %2 = location code, is-IS=Svæði %1 fannst ekki á staðsetningu %2.';
        LocationNextStepLbl: Label 'Check the location code and try again.', Comment = 'is-IS=Athugaðu kóða staðsetningar og reyndu aftur.';
        NotFoundNextStepLbl: Label 'Check the code named in the error and try again.', Comment = 'is-IS=Athugaðu kóðann sem villan nefnir og reyndu aftur.';
        Found: Boolean;
    begin
        Found := true;
        Location.SetLoadFields(Code, "Bin Mandatory");
        if not Location.Get(CopyStr(LocationCode, 1, MaxStrLen(Location.Code))) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(LocationMissingLbl, LocationCode), 'locationCode', LocationCode, '', LocationNextStepLbl);
            Found := false;
        end;
        Item.SetLoadFields("No.", "Base Unit of Measure", "Item Tracking Code");
        if not Item.Get(CopyStr(ItemNo, 1, MaxStrLen(Item."No."))) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(ItemMissingLbl, ItemNo), 'itemNo', ItemNo, '', NotFoundNextStepLbl);
            Found := false;
        end;
        if not Found then
            exit(false);
        if VariantCode <> '' then
            if not ItemVariant.Get(Item."No.", CopyStr(VariantCode, 1, MaxStrLen(ItemVariant.Code))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(VariantMissingLbl, VariantCode, Item."No."), 'variantCode', VariantCode, '', NotFoundNextStepLbl);
                Found := false;
            end;
        if UnitOfMeasureCode = '' then
            UnitOfMeasureCode := Item."Base Unit of Measure"
        else
            if not ItemUnitOfMeasure.Get(Item."No.", CopyStr(UnitOfMeasureCode, 1, MaxStrLen(ItemUnitOfMeasure.Code))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(UnitMissingLbl, UnitOfMeasureCode, Item."No."), 'unitOfMeasureCode', UnitOfMeasureCode, '', NotFoundNextStepLbl);
                Found := false;
            end;
        if BinCode <> '' then
            if not Bin.Get(Location.Code, CopyStr(BinCode, 1, MaxStrLen(Bin.Code))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(BinMissingLbl, BinCode, Location.Code), 'binCode', BinCode, '', NotFoundNextStepLbl);
                Found := false;
            end;
        if ZoneCode <> '' then
            if not Zone.Get(Location.Code, CopyStr(ZoneCode, 1, MaxStrLen(Zone.Code))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(ZoneMissingLbl, ZoneCode, Location.Code), 'zoneCode', ZoneCode, '', NotFoundNextStepLbl);
                Found := false;
            end;
        exit(Found);
    end;

    local procedure SetTracking(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; LotNo: Text; SerialNo: Text; PackageNo: Text)
    begin
        Clear(TempTrackingSetup);
        TempWhseItemTrackingLine.Reset();
        TempWhseItemTrackingLine.DeleteAll();
        Clear(TempWhseItemTrackingLine);
        HasTrackingFilter := (LotNo <> '') or (SerialNo <> '') or (PackageNo <> '');
        TempWhseItemTrackingLine.Init();
        TempWhseItemTrackingLine."Entry No." := 1;
        TempWhseItemTrackingLine."Item No." := ItemNo;
        TempWhseItemTrackingLine."Location Code" := LocationCode;
        TempWhseItemTrackingLine."Variant Code" := VariantCode;
        TempWhseItemTrackingLine."Lot No." := CopyStr(LotNo, 1, MaxStrLen(TempWhseItemTrackingLine."Lot No."));
        TempWhseItemTrackingLine."Serial No." := CopyStr(SerialNo, 1, MaxStrLen(TempWhseItemTrackingLine."Serial No."));
        TempWhseItemTrackingLine."Package No." := CopyStr(PackageNo, 1, MaxStrLen(TempWhseItemTrackingLine."Package No."));
        TempWhseItemTrackingLine.Insert();
        TempTrackingSetup."Lot No." := TempWhseItemTrackingLine."Lot No.";
        TempTrackingSetup."Serial No." := TempWhseItemTrackingLine."Serial No.";
        TempTrackingSetup."Package No." := TempWhseItemTrackingLine."Package No.";
    end;

    local procedure WriteAvailability(var Argument: Record "Message Argument ori"; Location: Record Location; Item: Record Item; VariantCode: Code[10]; UnitOfMeasureCode: Code[10]; BinCode: Code[20]; ZoneCode: Code[10]; LotNo: Text; SerialNo: Text; PackageNo: Text; IncludeBins: Boolean; IncludeTracking: Boolean)
    var
        WhseAvailabilityMgt: Codeunit "Warehouse Availability Mgt.";
        ResponseJson: JsonObject;
        QtyPerUnit: Decimal;
        QtyOnBlockedTracking: Decimal;
        NoBinsLbl: Label 'The location has no bins, so the quantities are inventory quantities of the location and bins is empty.', Comment = 'is-IS=Staðsetningin er án hólfa, því eru magntölur birgðamagn staðsetningarinnar og hólfalistinn er tómur.';
    begin
        QtyPerUnit := QtyPerUnitOfMeasure(Item."No.", UnitOfMeasureCode);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('itemNo', Item."No.");
        ResponseJson.Add('variantCode', VariantCode);
        ResponseJson.Add('locationCode', Location.Code);
        ResponseJson.Add('baseUnitOfMeasure', Item."Base Unit of Measure");
        ResponseJson.Add('unitOfMeasureCode', UnitOfMeasureCode);
        ResponseJson.Add('qtyInWarehouse', InUnit(QtyInWarehouse(Location, Item, VariantCode), QtyPerUnit));
        ResponseJson.Add('qtyOnPicks', InUnit(WhseAvailabilityMgt.CalcQtyAssgndtoPick(Location, Item."No.", VariantCode, ''), QtyPerUnit));
        ResponseJson.Add('qtyOnDedicatedBins', InUnit(QtyOnDedicatedBins(Location, Item."No.", VariantCode), QtyPerUnit));
        QtyOnBlockedTracking := QtyOnBlockedTrackingFor(Location, Item."No.", VariantCode);
        ResponseJson.Add('qtyOnBlockedBins', InUnit(WhseAvailabilityMgt.CalcQtyOnBlockedITOrOnBlockedOutbndBins(Location.Code, Item."No.", VariantCode, TempTrackingSetup) + QtyOnBlockedTracking, QtyPerUnit));
        ResponseJson.Add('qtyReservedOnInventory', InUnit(QtyReservedOnInventory(Location.Code, Item."No.", VariantCode), QtyPerUnit));
        ResponseJson.Add('qtyInReceiveShipQcBins', InUnit(QtyInSpecialBins(Location, Item."No.", VariantCode), QtyPerUnit));
        ResponseJson.Add('qtyAvailableToPick', InUnit(QtyAvailableToPick(Location, Item."No.", VariantCode), QtyPerUnit));
        if Location."Bin Mandatory" then begin
            if IncludeBins then
                ResponseJson.Add('bins', BinsJson(Location.Code, Item."No.", VariantCode, BinCode, ZoneCode, QtyPerUnit));
        end else begin
            ResponseJson.Add('note', NoBinsLbl);
            if IncludeBins then
                ResponseJson.Add('bins', EmptyArray());
        end;
        if IncludeTracking then
            ResponseJson.Add('tracking', TrackingJson(Location, Item, VariantCode, BinCode, ZoneCode, LotNo, SerialNo, PackageNo, QtyPerUnit));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure EmptyArray(): JsonArray
    var
        Empty: JsonArray;
    begin
        exit(Empty);
    end;

    local procedure QtyPerUnitOfMeasure(ItemNo: Code[20]; UnitOfMeasureCode: Code[10]): Decimal
    var
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        ItemUnitOfMeasure.SetLoadFields("Qty. per Unit of Measure");
        if ItemUnitOfMeasure.Get(ItemNo, UnitOfMeasureCode) then
            if ItemUnitOfMeasure."Qty. per Unit of Measure" <> 0 then
                exit(ItemUnitOfMeasure."Qty. per Unit of Measure");
        exit(1);
    end;

    local procedure InUnit(BaseQuantity: Decimal; QtyPerUnit: Decimal): Decimal
    begin
        if QtyPerUnit = 1 then
            exit(BaseQuantity);
        exit(Round(BaseQuantity / QtyPerUnit, 0.00001));
    end;

    local procedure QtyInWarehouse(Location: Record Location; Item: Record Item; VariantCode: Code[10]): Decimal
    var
        WarehouseEntry: Record "Warehouse Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        if Location."Bin Mandatory" then begin
            WarehouseEntry.ReadIsolation := IsolationLevel::ReadCommitted;
            WarehouseEntry.SetCurrentKey("Item No.", "Location Code", "Variant Code");
            WarehouseEntry.SetRange("Item No.", Item."No.");
            WarehouseEntry.SetRange("Location Code", Location.Code);
            WarehouseEntry.SetRange("Variant Code", VariantCode);
            SetEntryTracking(WarehouseEntry);
            WarehouseEntry.CalcSums("Qty. (Base)");
            exit(WarehouseEntry."Qty. (Base)");
        end;
        ItemLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Location Code", Location.Code);
        ItemLedgerEntry.SetRange("Variant Code", VariantCode);
        ItemLedgerEntry.SetRange(Open, true);
        if HasTrackingFilter then begin
            if TempWhseItemTrackingLine."Lot No." <> '' then
                ItemLedgerEntry.SetRange("Lot No.", TempWhseItemTrackingLine."Lot No.");
            if TempWhseItemTrackingLine."Serial No." <> '' then
                ItemLedgerEntry.SetRange("Serial No.", TempWhseItemTrackingLine."Serial No.");
            if TempWhseItemTrackingLine."Package No." <> '' then
                ItemLedgerEntry.SetRange("Package No.", TempWhseItemTrackingLine."Package No.");
        end;
        ItemLedgerEntry.CalcSums(Quantity);
        exit(ItemLedgerEntry.Quantity);
    end;

    local procedure SetEntryTracking(var WarehouseEntry: Record "Warehouse Entry")
    begin
        if not HasTrackingFilter then
            exit;
        if TempWhseItemTrackingLine."Lot No." <> '' then
            WarehouseEntry.SetRange("Lot No.", TempWhseItemTrackingLine."Lot No.");
        if TempWhseItemTrackingLine."Serial No." <> '' then
            WarehouseEntry.SetRange("Serial No.", TempWhseItemTrackingLine."Serial No.");
        if TempWhseItemTrackingLine."Package No." <> '' then
            WarehouseEntry.SetRange("Package No.", TempWhseItemTrackingLine."Package No.");
    end;

    local procedure QtyOnDedicatedBins(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        WhseAvailabilityMgt: Codeunit "Warehouse Availability Mgt.";
    begin
        if not Location."Bin Mandatory" then
            exit(0);
        if HasTrackingFilter then
            exit(WhseAvailabilityMgt.CalcQtyOnDedicatedBins(Location.Code, ItemNo, VariantCode, TempTrackingSetup));
        exit(WhseAvailabilityMgt.CalcQtyOnDedicatedBins(Location.Code, ItemNo, VariantCode));
    end;

    local procedure QtyOnBlockedTrackingFor(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        WhseAvailabilityMgt: Codeunit "Warehouse Availability Mgt.";
    begin
        if HasTrackingFilter then
            exit(WhseAvailabilityMgt.CalcQtyOnBlockedItemTracking(Location.Code, ItemNo, VariantCode, TempTrackingSetup));
        exit(WhseAvailabilityMgt.CalcQtyOnBlockedItemTracking(Location.Code, ItemNo, VariantCode));
    end;

    local procedure QtyReservedOnInventory(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        Item: Record Item;
    begin
        Item.SetLoadFields("No.");
        Item.Get(ItemNo);
        Item.SetRange("Location Filter", LocationCode);
        Item.SetRange("Variant Filter", VariantCode);
        Item.CalcFields("Reserved Qty. on Inventory");
        exit(Item."Reserved Qty. on Inventory");
    end;

    local procedure QtyInSpecialBins(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        TempBinContentBuffer: Record "Bin Content Buffer" temporary;
        WhseAvailabilityMgt: Codeunit "Warehouse Availability Mgt.";
    begin
        if not Location."Bin Mandatory" then
            exit(0);
        exit(WhseAvailabilityMgt.CalcQtyOnSpecialBinsOnLocation(Location.Code, ItemNo, VariantCode, TempTrackingSetup, TempBinContentBuffer));
    end;

    local procedure QtyAvailableToPick(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        CreatePick: Codeunit "Create Pick";
    begin
        if not Location."Bin Mandatory" then
            exit(InventoryAvailable(Location, ItemNo, VariantCode));
        if HasTrackingFilter then
            exit(CreatePick.CalcTotalAvailQtyToPick(Location.Code, ItemNo, VariantCode, TempWhseItemTrackingLine, 0, 0, '', 0, 0, 0, Location."Bin Mandatory"));
        exit(CreatePick.CalcTotalAvailQtyToPick(Location.Code, ItemNo, VariantCode, 0, 0, '', 0, 0, 0, Location."Bin Mandatory"));
    end;

    local procedure InventoryAvailable(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]): Decimal
    var
        Item: Record Item;
        WarehouseActivityLine: Record "Warehouse Activity Line";
        WhseAvailabilityMgt: Codeunit "Warehouse Availability Mgt.";
    begin
        Item.Get(ItemNo);
        exit(WhseAvailabilityMgt.CalcInvtAvailQty(Item, Location, VariantCode, WarehouseActivityLine));
    end;

    local procedure BinsJson(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; BinCode: Code[20]; ZoneCode: Code[10]; QtyPerUnit: Decimal) BinArray: JsonArray
    var
        BinContent: Record "Bin Content";
        Bin: Record Bin;
        BinCodes: List of [Text];
        Quantities: Dictionary of [Text, Decimal];
        Available: Dictionary of [Text, Decimal];
        PickQuantities: Dictionary of [Text, Decimal];
        RowKey: Text;
        BinJson: JsonObject;
    begin
        BinContent.ReadIsolation := IsolationLevel::ReadCommitted;
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", VariantCode);
        if BinCode <> '' then
            BinContent.SetRange("Bin Code", BinCode);
        if ZoneCode <> '' then
            BinContent.SetRange("Zone Code", ZoneCode);
        if HasTrackingFilter then begin
            if TempWhseItemTrackingLine."Lot No." <> '' then
                BinContent.SetRange("Lot No. Filter", TempWhseItemTrackingLine."Lot No.");
            if TempWhseItemTrackingLine."Serial No." <> '' then
                BinContent.SetRange("Serial No. Filter", TempWhseItemTrackingLine."Serial No.");
            if TempWhseItemTrackingLine."Package No." <> '' then
                BinContent.SetRange("Package No. Filter", TempWhseItemTrackingLine."Package No.");
        end;
        BinContent.SetAutoCalcFields("Quantity (Base)", "Pick Quantity (Base)");
        if BinContent.FindSet() then
            repeat
                RowKey := BinContent."Bin Code";
                if not Quantities.ContainsKey(RowKey) then begin
                    BinCodes.Add(RowKey);
                    Quantities.Add(RowKey, 0);
                    Available.Add(RowKey, 0);
                    PickQuantities.Add(RowKey, 0);
                end;
                Quantities.Set(RowKey, Quantities.Get(RowKey) + BinContent."Quantity (Base)");
                Available.Set(RowKey, Available.Get(RowKey) + BinContent.CalcQtyAvailToTake(0));
                PickQuantities.Set(RowKey, PickQuantities.Get(RowKey) + BinContent."Pick Quantity (Base)");
            until BinContent.Next() = 0;
        foreach RowKey in BinCodes do begin
            Clear(BinJson);
            Bin.SetLoadFields("Location Code", Code, "Zone Code", "Bin Type Code", "Block Movement", Dedicated);
            Bin.Get(LocationCode, CopyStr(RowKey, 1, MaxStrLen(Bin.Code)));
            BinJson.Add('binCode', Bin.Code);
            BinJson.Add('zoneCode', Bin."Zone Code");
            BinJson.Add('binTypeCode', Bin."Bin Type Code");
            BinJson.Add('quantity', InUnit(Quantities.Get(RowKey), QtyPerUnit));
            BinJson.Add('qtyAvailableToTake', InUnit(Available.Get(RowKey), QtyPerUnit));
            BinJson.Add('pickQty', InUnit(PickQuantities.Get(RowKey), QtyPerUnit));
            BinJson.Add('blockMovement', BlockMovementText(Bin));
            BinJson.Add('dedicated', Bin.Dedicated);
            BinArray.Add(BinJson);
        end;
    end;

    local procedure BlockMovementText(Bin: Record Bin): Text
    begin
        case Bin."Block Movement" of
            Bin."Block Movement"::Inbound:
                exit('Inbound');
            Bin."Block Movement"::Outbound:
                exit('Outbound');
            Bin."Block Movement"::All:
                exit('All');
            else
                exit('');
        end;
    end;

    local procedure TrackingJson(Location: Record Location; Item: Record Item; VariantCode: Code[10]; BinCode: Code[20]; ZoneCode: Code[10]; LotNo: Text; SerialNo: Text; PackageNo: Text; QtyPerUnit: Decimal) TrackingArray: JsonArray
    var
        WarehouseEntry: Record "Warehouse Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        TempRow: Record "Whse. Item Tracking Line" temporary;
        Quantities: Dictionary of [Text, Decimal];
        Keys: List of [Text];
        RowKey: Text;
        RowJson: JsonObject;
        RowQty: Decimal;
    begin
        if Item."Item Tracking Code" = '' then
            exit;
        if Location."Bin Mandatory" then begin
            WarehouseEntry.ReadIsolation := IsolationLevel::ReadCommitted;
            WarehouseEntry.SetCurrentKey("Item No.", "Location Code", "Variant Code");
            WarehouseEntry.SetRange("Item No.", Item."No.");
            WarehouseEntry.SetRange("Location Code", Location.Code);
            WarehouseEntry.SetRange("Variant Code", VariantCode);
            if BinCode <> '' then
                WarehouseEntry.SetRange("Bin Code", BinCode);
            if ZoneCode <> '' then
                WarehouseEntry.SetRange("Zone Code", ZoneCode);
            SetEntryTracking(WarehouseEntry);
            if WarehouseEntry.FindSet() then
                repeat
                    RowKey := TrackingKey(WarehouseEntry."Lot No.", WarehouseEntry."Serial No.", WarehouseEntry."Package No.");
                    if not Quantities.ContainsKey(RowKey) then begin
                        Keys.Add(RowKey);
                        Quantities.Add(RowKey, 0);
                        TempRow.Init();
                        TempRow."Entry No." := Keys.Count();
                        TempRow."Lot No." := WarehouseEntry."Lot No.";
                        TempRow."Serial No." := WarehouseEntry."Serial No.";
                        TempRow."Package No." := WarehouseEntry."Package No.";
                        TempRow."Expiration Date" := WarehouseEntry."Expiration Date";
                        TempRow.Insert();
                    end;
                    Quantities.Set(RowKey, Quantities.Get(RowKey) + WarehouseEntry."Qty. (Base)");
                    if WarehouseEntry."Expiration Date" <> 0D then begin
                        TempRow.Get(Keys.IndexOf(RowKey));
                        TempRow."Expiration Date" := WarehouseEntry."Expiration Date";
                        TempRow.Modify();
                    end;
                until WarehouseEntry.Next() = 0;
        end else begin
            ItemLedgerEntry.ReadIsolation := IsolationLevel::ReadCommitted;
            ItemLedgerEntry.SetRange("Item No.", Item."No.");
            ItemLedgerEntry.SetRange("Location Code", Location.Code);
            ItemLedgerEntry.SetRange("Variant Code", VariantCode);
            ItemLedgerEntry.SetRange(Open, true);
            if LotNo <> '' then
                ItemLedgerEntry.SetRange("Lot No.", LotNo);
            if SerialNo <> '' then
                ItemLedgerEntry.SetRange("Serial No.", SerialNo);
            if PackageNo <> '' then
                ItemLedgerEntry.SetRange("Package No.", PackageNo);
            if ItemLedgerEntry.FindSet() then
                repeat
                    RowKey := TrackingKey(ItemLedgerEntry."Lot No.", ItemLedgerEntry."Serial No.", ItemLedgerEntry."Package No.");
                    if not Quantities.ContainsKey(RowKey) then begin
                        Keys.Add(RowKey);
                        Quantities.Add(RowKey, 0);
                        TempRow.Init();
                        TempRow."Entry No." := Keys.Count();
                        TempRow."Lot No." := ItemLedgerEntry."Lot No.";
                        TempRow."Serial No." := ItemLedgerEntry."Serial No.";
                        TempRow."Package No." := ItemLedgerEntry."Package No.";
                        TempRow."Expiration Date" := ItemLedgerEntry."Expiration Date";
                        TempRow.Insert();
                    end;
                    Quantities.Set(RowKey, Quantities.Get(RowKey) + ItemLedgerEntry.Quantity);
                until ItemLedgerEntry.Next() = 0;
        end;
        foreach RowKey in Keys do begin
            TempRow.Get(Keys.IndexOf(RowKey));
            RowQty := Quantities.Get(RowKey);
            if (RowQty <> 0) and not IsBlocked(Item."No.", VariantCode, TempRow) then begin
                Clear(RowJson);
                RowJson.Add('lotNo', TempRow."Lot No.");
                RowJson.Add('serialNo', TempRow."Serial No.");
                RowJson.Add('packageNo', TempRow."Package No.");
                if TempRow."Expiration Date" <> 0D then
                    RowJson.Add('expirationDate', Format(TempRow."Expiration Date", 0, '<Year4>-<Month,2>-<Day,2>'))
                else
                    RowJson.Add('expirationDate', '');
                RowJson.Add('quantity', InUnit(RowQty, QtyPerUnit));
                RowJson.Add('qtyAvailableToPick', InUnit(QtyAvailableToPickFor(Location, Item."No.", VariantCode, TempRow), QtyPerUnit));
                TrackingArray.Add(RowJson);
            end;
        end;
    end;

    local procedure TrackingKey(LotNo: Code[50]; SerialNo: Code[50]; PackageNo: Code[50]): Text
    begin
        exit(LotNo + '|' + SerialNo + '|' + PackageNo);
    end;

    local procedure IsBlocked(ItemNo: Code[20]; VariantCode: Code[10]; Row: Record "Whse. Item Tracking Line"): Boolean
    var
        LotNoInformation: Record "Lot No. Information";
        SerialNoInformation: Record "Serial No. Information";
        PackageNoInformation: Record "Package No. Information";
    begin
        if Row."Lot No." <> '' then
            if LotNoInformation.Get(ItemNo, VariantCode, Row."Lot No.") then
                if LotNoInformation.Blocked then
                    exit(true);
        if Row."Serial No." <> '' then
            if SerialNoInformation.Get(ItemNo, VariantCode, Row."Serial No.") then
                if SerialNoInformation.Blocked then
                    exit(true);
        if Row."Package No." <> '' then
            if PackageNoInformation.Get(ItemNo, VariantCode, Row."Package No.") then
                if PackageNoInformation.Blocked then
                    exit(true);
        exit(false);
    end;

    local procedure QtyAvailableToPickFor(Location: Record Location; ItemNo: Code[20]; VariantCode: Code[10]; Row: Record "Whse. Item Tracking Line"): Decimal
    var
        TempRowLine: Record "Whse. Item Tracking Line" temporary;
        CreatePick: Codeunit "Create Pick";
    begin
        TempRowLine.Init();
        TempRowLine."Entry No." := 1;
        TempRowLine."Item No." := ItemNo;
        TempRowLine."Location Code" := Location.Code;
        TempRowLine."Variant Code" := VariantCode;
        TempRowLine."Lot No." := Row."Lot No.";
        TempRowLine."Serial No." := Row."Serial No.";
        TempRowLine."Package No." := Row."Package No.";
        TempRowLine.Insert();
        exit(CreatePick.CalcTotalAvailQtyToPick(Location.Code, ItemNo, VariantCode, TempRowLine, 0, 0, '', 0, 0, 0, Location."Bin Mandatory"));
    end;

    /// <summary>
    /// Adds a related type only when that name exists on Message Type ori.
    /// Warehouse does not depend on Bifrost Inventory, so its types are absent until that app is installed (#107).
    /// </summary>
    local procedure AddInstalledRelated(var Related: JsonArray; ContractMgt: Codeunit "Msg Contract Mgt ori"; TypeName: Text; UseInsteadWhen: Text)
    begin
        if not Enum::"Message Type ori".Names().Contains(TypeName) then
            exit;
        Related.Add(ContractMgt.RelatedEntry(TypeName, UseInsteadWhen));
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        MsgValues: Codeunit "Whse Msg Values ori";
        AllowedKeys: List of [Text];
    begin
        AllowedKeys.Add('locationCode');
        AllowedKeys.Add('itemNo');
        AllowedKeys.Add('variantCode');
        AllowedKeys.Add('unitOfMeasureCode');
        AllowedKeys.Add('binCode');
        AllowedKeys.Add('zoneCode');
        AllowedKeys.Add('lotNo');
        AllowedKeys.Add('serialNo');
        AllowedKeys.Add('packageNo');
        AllowedKeys.Add('includeBins');
        AllowedKeys.Add('includeTracking');
        MsgValues.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
    end;
}
