namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Tracking;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.InternalDocument;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Tracking;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Shared validation, creation and response logic for Warehouse.InternalPutaway.Create and Warehouse.InternalPick.Create (#106).
/// The put-away takes from a from-bin; the pick places into a to-bin. Both release the internal document and can create the activity.
/// </summary>
codeunit 10078405 "Whse Internal Doc Helper ori"
{
    Access = Internal;

    var
        RefusedNextStepLbl: Label 'Read the returned text, correct the bin, the bin content or the quantity, and send the request again. Nothing was written.', Comment = 'is-IS=Lestu textann sem skilaði sér, leiðréttu hólfið, hólfainnihaldið eða magnið og sendu beiðnina aftur. Ekkert var skrifað.';
        NotFoundNextStepLbl: Label 'Check the code with Warehouse.BinContent.Get or Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu kóðann með Warehouse.BinContent.Get eða Warehouse.Bin.Get.';
        FormatNextStepLbl: Label 'Send text for codes, numbers for quantities and true or false for switches.', Comment = 'is-IS=Sendu texta fyrir kóða, tölur fyrir magn og true eða false fyrir rofa.';

    /// <summary>Validates the request and fills the payload for the write. Every problem is collected on the argument.</summary>
    /// <param name="RequestJson">The request data.</param>
    /// <param name="Argument">Collects the problems.</param>
    /// <param name="IsPick">True for the internal pick, false for the internal put-away.</param>
    /// <param name="Payload">Receives the validated payload.</param>
    internal procedure ReadRequest(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; IsPick: Boolean; var Payload: JsonObject)
    var
        Context: Codeunit "Whse Write Context ori";
        LocationCode: Code[10];
        ZoneCode: Code[10];
        BinCode: Code[20];
        AssignedUserId: Text;
        SortingText: Text;
        DueDate: Date;
        Release: Boolean;
        CreateActivity: Boolean;
        Present: Boolean;
        Lines: JsonArray;
        Token: JsonToken;
        HasLines: Boolean;
        HasBinContent: Boolean;
        DirectedLbl: Label 'Location %1 does not use directed put-away and pick.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki beina innsetningu og tínslu.';
        DirectedNextStepLbl: Label 'Use Warehouse.InventoryMovement.Create for basic warehouse locations.', Comment = 'is-IS=Notaðu Warehouse.InventoryMovement.Create fyrir einfaldar vöruhúsastaðsetningar.';
        LinesMissingLbl: Label 'Send lines or getBinContent.', Comment = 'is-IS=Sendu lines eða getBinContent.';
        LinesMissingPickLbl: Label 'Send at least one line.', Comment = 'is-IS=Sendu að minnsta kosti eina línu.';
        BothLbl: Label 'Send lines or getBinContent, not both.', Comment = 'is-IS=Sendu lines eða getBinContent, ekki hvort tveggja.';
        ActivityNeedsReleaseLbl: Label 'createActivity needs a released document. Do not send release false together with createActivity true.', Comment = 'is-IS=createActivity þarf útgefið skjal. Ekki senda release false ásamt createActivity true.';
        ActivityNeedsReleaseNextStepLbl: Label 'Send release true, or leave createActivity out.', Comment = 'is-IS=Sendu release true eða slepptu createActivity.';
        ActivityOnlyLbl: Label '%1 is only used with createActivity true.', Comment = '%1 = parameter, is-IS=%1 er aðeins notað með createActivity true.';
        ActivityOnlyNextStepLbl: Label 'Send createActivity true, or leave the parameter out.', Comment = 'is-IS=Sendu createActivity true eða slepptu færibreytunni.';
    begin
        Clear(Payload);
        RefuseUnknownKeys(RequestJson, Argument, IsPick);
        if not TryResolveLocation(RequestJson, Argument, LocationCode) then
            exit;
        if not LocationIsDirected(LocationCode) then begin
            // A basic location is the whole answer. Further errors would hide the required next step.
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(DirectedLbl, LocationCode), 'locationCode', LocationCode, '', DirectedNextStepLbl);
            exit;
        end;
        if IsPick then
            ReadZoneAndBin(RequestJson, Argument, LocationCode, 'toZoneCode', 'toBinCode', true, ZoneCode, BinCode)
        else
            ReadZoneAndBin(RequestJson, Argument, LocationCode, 'fromZoneCode', 'fromBinCode', false, ZoneCode, BinCode);
        Release := true;
        if Context.ReadBoolean(RequestJson, 'release', Argument, Release, Present, 'release') then
            if not Present then
                Release := true;
        CreateActivity := false;
        if Context.ReadBoolean(RequestJson, 'createActivity', Argument, CreateActivity, Present, 'createActivity') then
            if not Present then
                CreateActivity := false;
        if CreateActivity and not Release then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, ActivityNeedsReleaseLbl, 'release', 'false', '', ActivityNeedsReleaseNextStepLbl);
        Context.ReadText(RequestJson, 'assignedUserId', 50, Argument, AssignedUserId, Present, 'assignedUserId');
        if Present and not CreateActivity then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ActivityOnlyLbl, 'assignedUserId'), 'assignedUserId', AssignedUserId, '', ActivityOnlyNextStepLbl);
        if Present then
            CheckUser(Argument, AssignedUserId);
        Context.ReadText(RequestJson, 'sortingMethod', 30, Argument, SortingText, Present, 'sortingMethod');
        if Present and not CreateActivity then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ActivityOnlyLbl, 'sortingMethod'), 'sortingMethod', SortingText, '', ActivityOnlyNextStepLbl);
        if Present then
            CheckSortingMethod(Argument, SortingText);
        if IsPick then
            if not Context.ReadDate(RequestJson, 'dueDate', Argument, DueDate, Present, 'dueDate') then
                DueDate := 0D;

        HasLines := false;
        if RequestJson.Get('lines', Token) then
            HasLines := true;
        HasBinContent := (not IsPick) and RequestJson.Contains('getBinContent');
        if HasLines and HasBinContent then
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, BothLbl, 'getBinContent', '', '', BothLbl);
        if not HasLines and not HasBinContent then
            if IsPick then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, LinesMissingPickLbl, 'lines', '', '', LinesMissingPickLbl)
            else
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, LinesMissingLbl, 'lines', '', '', LinesMissingLbl);
        if HasLines then
            ReadLines(RequestJson, Argument, LocationCode, BinCode, IsPick, Lines);
        if HasBinContent then
            ReadBinContentRequest(RequestJson, Argument, LocationCode, Payload);

        Payload.Add('locationCode', LocationCode);
        Payload.Add('zoneCode', ZoneCode);
        Payload.Add('binCode', BinCode);
        Payload.Add('release', Release);
        Payload.Add('createActivity', CreateActivity);
        Payload.Add('assignedUserId', UpperCase(AssignedUserId));
        Payload.Add('sortingMethod', SortingText);
        if DueDate <> 0D then
            Payload.Add('dueDate', Format(DueDate, 0, 9));
        Payload.Add('lines', Lines);
    end;

    local procedure TryResolveLocation(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        Context: Codeunit "Whse Write Context ori";
        LocationText: Text;
        SubjectText: Text;
        Present: Boolean;
        MissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode of a location with directed put-away and pick.', Comment = 'is-IS=Sendu locationCode staðsetningar með beinni innsetningu og tínslu.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
    begin
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'locationCode', MaxStrLen(Location.Code), Argument, LocationText, Present, 'locationCode') then
            exit(false);
        if Present and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationText)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        if not Present then
            LocationText := SubjectText;
        if LocationText = '' then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'locationCode', '', '', MissingNextStepLbl);
            exit(false);
        end;
        LocationCode := CopyStr(UpperCase(LocationText), 1, MaxStrLen(Location.Code));
        Location.SetLoadFields(Code);
        if Location.Get(LocationCode) then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
        Clear(LocationCode);
        exit(false);
    end;

    local procedure LocationIsDirected(LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
    begin
        Location.SetLoadFields("Directed Put-away and Pick");
        if not Location.Get(LocationCode) then
            exit(false);
        exit(Location."Directed Put-away and Pick");
    end;

    local procedure ReadZoneAndBin(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; ZoneKey: Text; BinKey: Text; Inbound: Boolean; var ZoneCode: Code[10]; var BinCode: Code[20])
    var
        Zone: Record Zone;
        Bin: Record Bin;
        Context: Codeunit "Whse Write Context ori";
        ZoneText: Text;
        BinText: Text;
        ZonePresent: Boolean;
        BinPresent: Boolean;
        NotFoundLbl: Label '%1 %2 was not found at location %3.', Comment = '%1 = table, %2 = code, %3 = location, is-IS=%1 %2 fannst ekki á staðsetningu %3.';
        ZoneConflictLbl: Label 'Bin %1 is in zone %2, not in zone %3.', Comment = '%1 = bin, %2 = zone of the bin, %3 = zone sent, is-IS=Hólf %1 er á svæði %2, ekki á svæði %3.';
        ZoneConflictNextStepLbl: Label 'Send the zone of the bin, or leave the zone out.', Comment = 'is-IS=Sendu svæði hólfsins eða slepptu svæðinu.';
    begin
        Clear(ZoneCode);
        Clear(BinCode);
        Context.ReadText(RequestJson, ZoneKey, MaxStrLen(Zone.Code), Argument, ZoneText, ZonePresent, ZoneKey);
        Context.ReadText(RequestJson, BinKey, MaxStrLen(Bin.Code), Argument, BinText, BinPresent, BinKey);
        if ZonePresent then begin
            ZoneCode := CopyStr(UpperCase(ZoneText), 1, MaxStrLen(ZoneCode));
            if not Zone.Get(LocationCode, ZoneCode) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Zone.TableCaption(), ZoneCode, LocationCode), ZoneKey, ZoneCode, '', NotFoundNextStepLbl);
                Clear(ZoneCode);
            end;
        end;
        if not BinPresent then
            exit;
        BinCode := CopyStr(UpperCase(BinText), 1, MaxStrLen(BinCode));
        if not Bin.Get(LocationCode, BinCode) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), BinCode, LocationCode), BinKey, BinCode, '', NotFoundNextStepLbl);
            Clear(BinCode);
            exit;
        end;
        if ZonePresent and (ZoneCode <> '') and (Bin."Zone Code" <> ZoneCode) then
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(ZoneConflictLbl, BinCode, Bin."Zone Code", ZoneCode), ZoneKey, ZoneCode, Bin."Zone Code", ZoneConflictNextStepLbl);
        ZoneCode := Bin."Zone Code";
        CheckBinNotBlocked(Argument, Bin, Inbound, BinKey);
    end;

    local procedure CheckBinNotBlocked(var Argument: Record "Message Argument ori"; Bin: Record Bin; Inbound: Boolean; ParameterName: Text)
    var
        BlockedLbl: Label 'Bin %1 is blocked for movement (%2).', Comment = '%1 = bin, %2 = block movement value, is-IS=Hólf %1 er lokað fyrir hreyfingu (%2).';
    begin
        if Bin."Block Movement" = Bin."Block Movement"::All then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BlockedLbl, Bin.Code, Format(Bin."Block Movement")), ParameterName, Bin.Code, '', RefusedNextStepLbl);
        if Inbound and (Bin."Block Movement" = Bin."Block Movement"::Inbound) then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BlockedLbl, Bin.Code, Format(Bin."Block Movement")), ParameterName, Bin.Code, '', RefusedNextStepLbl);
        if (not Inbound) and (Bin."Block Movement" = Bin."Block Movement"::Outbound) then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BlockedLbl, Bin.Code, Format(Bin."Block Movement")), ParameterName, Bin.Code, '', RefusedNextStepLbl);
    end;

    local procedure CheckUser(var Argument: Record "Message Argument ori"; UserText: Text)
    var
        WarehouseEmployee: Record "Warehouse Employee";
        NotFoundLbl: Label 'User %1 is not a warehouse employee.', Comment = '%1 = user, is-IS=Notandinn %1 er ekki starfsmaður vöruhúss.';
    begin
        WarehouseEmployee.SetRange("User ID", CopyStr(UpperCase(UserText), 1, MaxStrLen(WarehouseEmployee."User ID")));
        if WarehouseEmployee.IsEmpty() then
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, UserText), 'assignedUserId', UserText, '', NotFoundNextStepLbl);
    end;

    local procedure CheckSortingMethod(var Argument: Record "Message Argument ori"; SortingText: Text)
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Context: Codeunit "Whse Write Context ori";
        Method: Enum "Whse. Activity Sorting Method";
        Name: Text;
        InvalidLbl: Label 'sortingMethod %1 is not a Business Central sorting method.', Comment = '%1 = value, is-IS=sortingMethod %1 er ekki röðunaraðferð í Business Central.';
    begin
        foreach Name in Method.Names() do
            if Context.SameName(SortingText, Name) then
                exit;
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidLbl, SortingText), 'sortingMethod', SortingText, '', Parts.SortingMethodNextStep());
    end;

    local procedure ReadLines(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; HeaderBinCode: Code[20]; IsPick: Boolean; var Planned: JsonArray)
    var
        Values: Codeunit "Whse Msg Values ori";
        Lines: JsonArray;
        LineObject: JsonObject;
        Present: Boolean;
        Index: Integer;
        EmptyLbl: Label 'lines must hold at least one line.', Comment = 'is-IS=lines verður að innihalda að minnsta kosti eina línu.';
    begin
        if not Values.ReadArray(RequestJson, 'lines', Argument, Lines, Present) then
            exit;
        if Lines.Count() = 0 then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, EmptyLbl, 'lines', '', '', EmptyLbl);
            exit;
        end;
        for Index := 0 to Lines.Count() - 1 do
            if Values.TryGetLineObject(Lines, Index, 'lines', Argument, LineObject) then
                ReadOneLine(LineObject, Index, Argument, LocationCode, HeaderBinCode, IsPick, Planned);
    end;

    local procedure ReadOneLine(LineObject: JsonObject; Index: Integer; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; HeaderBinCode: Code[20]; IsPick: Boolean; var Planned: JsonArray)
    var
        Item: Record Item;
        ItemVariant: Record "Item Variant";
        ItemUnit: Record "Item Unit of Measure";
        Bin: Record Bin;
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        AllowedKeys: List of [Text];
        PlannedLine: JsonObject;
        ItemNo: Text;
        VariantCode: Text;
        UnitCode: Text;
        BinText: Text;
        LotNo: Text;
        SerialNo: Text;
        PackageNo: Text;
        ItemPresent: Boolean;
        VariantPresent: Boolean;
        UnitPresent: Boolean;
        BinPresent: Boolean;
        LotPresent: Boolean;
        SerialPresent: Boolean;
        PackagePresent: Boolean;
        QuantityPresent: Boolean;
        Quantity: Decimal;
        LineBin: Code[20];
        Valid: Boolean;
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line position in the request, counted from 1, %2 = field, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send itemNo and quantity on every line, and a from-bin on the line or on the request.', Comment = 'is-IS=Sendu itemNo og quantity á hverri línu og frá-hólf á línunni eða í beiðninni.';
        MissingPickNextStepLbl: Label 'Send itemNo and quantity on every line.', Comment = 'is-IS=Sendu itemNo og quantity á hverri línu.';
        QuantityLbl: Label 'Quantity must be greater than zero.', Comment = 'is-IS=Magn verður að vera stærra en núll.';
        QuantityNextStepLbl: Label 'Send a quantity greater than zero.', Comment = 'is-IS=Sendu magn sem er stærra en núll.';
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table, %2 = value, is-IS=%1 %2 fannst ekki.';
        SerialQtyLbl: Label 'A line with serialNo must have a base quantity of 1.', Comment = 'is-IS=Lína með serialNo verður að hafa grunnmagnið 1.';
        SerialQtyNextStepLbl: Label 'Send one line for each serial number, with quantity 1 in the base unit.', Comment = 'is-IS=Sendu eina línu fyrir hvert raðnúmer, með magnið 1 í grunneiningu.';
    begin
        AllowedKeys.AddRange('itemNo', 'variantCode', 'unitOfMeasureCode', 'quantity', 'lotNo', 'serialNo', 'packageNo');
        if not IsPick then
            AllowedKeys.Add('fromBinCode');
        Values.RefuseUnknownKeys(LineObject, AllowedKeys, Argument, 'lines', Index);
        Context.ReadText(LineObject, 'itemNo', MaxStrLen(Item."No."), Argument, ItemNo, ItemPresent, Values.LineParameter('lines', Index, 'itemNo'));
        Context.ReadText(LineObject, 'variantCode', MaxStrLen(ItemVariant.Code), Argument, VariantCode, VariantPresent, Values.LineParameter('lines', Index, 'variantCode'));
        Context.ReadText(LineObject, 'unitOfMeasureCode', MaxStrLen(ItemUnit.Code), Argument, UnitCode, UnitPresent, Values.LineParameter('lines', Index, 'unitOfMeasureCode'));
        Context.ReadDecimal(LineObject, 'quantity', Argument, Quantity, QuantityPresent, Values.LineParameter('lines', Index, 'quantity'));
        Context.ReadText(LineObject, 'lotNo', 50, Argument, LotNo, LotPresent, Values.LineParameter('lines', Index, 'lotNo'));
        Context.ReadText(LineObject, 'serialNo', 50, Argument, SerialNo, SerialPresent, Values.LineParameter('lines', Index, 'serialNo'));
        Context.ReadText(LineObject, 'packageNo', 50, Argument, PackageNo, PackagePresent, Values.LineParameter('lines', Index, 'packageNo'));
        if not IsPick then
            Context.ReadText(LineObject, 'fromBinCode', MaxStrLen(Bin.Code), Argument, BinText, BinPresent, Values.LineParameter('lines', Index, 'fromBinCode'));
        Valid := true;
        if not ItemPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'itemNo'), Values.LineParameter('lines', Index, 'itemNo'), '', '', LineNextStep(IsPick, MissingNextStepLbl, MissingPickNextStepLbl));
            Valid := false;
        end;
        if not QuantityPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'quantity'), Values.LineParameter('lines', Index, 'quantity'), '', '', LineNextStep(IsPick, MissingNextStepLbl, MissingPickNextStepLbl));
            Valid := false;
        end else
            if Quantity <= 0 then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, QuantityLbl, Values.LineParameter('lines', Index, 'quantity'), Format(Quantity, 0, 9), '', QuantityNextStepLbl);
                Valid := false;
            end;
        if not IsPick then begin
            LineBin := HeaderBinCode;
            if BinPresent then
                LineBin := CopyStr(UpperCase(BinText), 1, MaxStrLen(LineBin));
            if LineBin = '' then begin
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'fromBinCode'), Values.LineParameter('lines', Index, 'fromBinCode'), '', '', MissingNextStepLbl);
                Valid := false;
            end else
                if BinPresent then
                    if not Bin.Get(LocationCode, LineBin) then begin
                        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), LineBin), Values.LineParameter('lines', Index, 'fromBinCode'), LineBin, '', NotFoundNextStepLbl);
                        Valid := false;
                    end else
                        CheckBinNotBlocked(Argument, Bin, false, Values.LineParameter('lines', Index, 'fromBinCode'));
        end;
        if ItemPresent then begin
            ItemNo := UpperCase(ItemNo);
            Item.SetLoadFields("No.", "Base Unit of Measure");
            if not Item.Get(CopyStr(ItemNo, 1, MaxStrLen(Item."No."))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemNo), Values.LineParameter('lines', Index, 'itemNo'), ItemNo, '', NotFoundNextStepLbl);
                Valid := false;
            end else begin
                VariantCode := UpperCase(VariantCode);
                if VariantPresent then
                    if not ItemVariant.Get(Item."No.", CopyStr(VariantCode, 1, MaxStrLen(ItemVariant.Code))) then begin
                        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemVariant.TableCaption(), VariantCode), Values.LineParameter('lines', Index, 'variantCode'), VariantCode, '', NotFoundNextStepLbl);
                        Valid := false;
                    end;
                UnitCode := UpperCase(UnitCode);
                if UnitCode = '' then
                    UnitCode := Item."Base Unit of Measure";
                if not ItemUnit.Get(Item."No.", CopyStr(UnitCode, 1, MaxStrLen(ItemUnit.Code))) then begin
                    Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemUnit.TableCaption(), UnitCode), Values.LineParameter('lines', Index, 'unitOfMeasureCode'), UnitCode, '', NotFoundNextStepLbl);
                    Valid := false;
                end else begin
                    if SerialPresent and QuantityPresent and (Quantity * ItemUnit."Qty. per Unit of Measure" <> 1) then begin
                        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, SerialQtyLbl, Values.LineParameter('lines', Index, 'quantity'), Format(Quantity, 0, 9), '', SerialQtyNextStepLbl);
                        Valid := false;
                    end;
                    if Valid and not IsPick then
                        CheckBinQuantity(Argument, Index, LocationCode, LineBin, Item."No.", VariantCode, LotNo, SerialNo, PackageNo, Quantity * ItemUnit."Qty. per Unit of Measure", Valid);
                end;
            end;
        end;
        if not Valid then
            exit;
        PlannedLine.Add('itemNo', ItemNo);
        PlannedLine.Add('variantCode', VariantCode);
        PlannedLine.Add('unitOfMeasureCode', UnitCode);
        PlannedLine.Add('quantity', Quantity);
        PlannedLine.Add('binCode', LineBin);
        PlannedLine.Add('lotNo', LotNo);
        PlannedLine.Add('serialNo', SerialNo);
        PlannedLine.Add('packageNo', PackageNo);
        Planned.Add(PlannedLine);
    end;

    local procedure LineNextStep(IsPick: Boolean; PutAwayNextStep: Text; PickNextStep: Text): Text
    begin
        if IsPick then
            exit(PickNextStep);
        exit(PutAwayNextStep);
    end;

    local procedure CheckBinQuantity(var Argument: Record "Message Argument ori"; Index: Integer; LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Text; LotNo: Text; SerialNo: Text; PackageNo: Text; RequestedBase: Decimal; var Valid: Boolean)
    var
        BinContent: Record "Bin Content";
        Values: Codeunit "Whse Msg Values ori";
        AvailableBase: Decimal;
        ShortLbl: Label 'Bin %1 holds %2 of item %3 in the base unit, less than the %4 asked for.', Comment = '%1 = bin, %2 = quantity in bin, %3 = item, %4 = quantity asked, is-IS=Hólf %1 inniheldur %2 af vöru %3 í grunneiningu, minna en þau %4 sem beðið var um.';
        ShortNextStepLbl: Label 'Read Warehouse.BinContent.Get for the bin and lower the quantity.', Comment = 'is-IS=Lestu Warehouse.BinContent.Get fyrir hólfið og lækkaðu magnið.';
    begin
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", BinCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", CopyStr(VariantCode, 1, MaxStrLen(BinContent."Variant Code")));
        if LotNo <> '' then
            BinContent.SetRange("Lot No. Filter", LotNo);
        if SerialNo <> '' then
            BinContent.SetRange("Serial No. Filter", SerialNo);
        if PackageNo <> '' then
            BinContent.SetRange("Package No. Filter", PackageNo);
        BinContent.SetAutoCalcFields("Quantity (Base)");
        if BinContent.FindSet() then
            repeat
                AvailableBase += BinContent."Quantity (Base)";
            until BinContent.Next() = 0;
        if AvailableBase >= RequestedBase then
            exit;
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(ShortLbl, BinCode, Format(AvailableBase, 0, 9), ItemNo, Format(RequestedBase, 0, 9)), Values.LineParameter('lines', Index, 'quantity'), Format(RequestedBase, 0, 9), Format(AvailableBase, 0, 9), ShortNextStepLbl);
        Valid := false;
    end;

    local procedure ReadBinContentRequest(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; var Payload: JsonObject)
    var
        Bin: Record Bin;
        Zone: Record Zone;
        Item: Record Item;
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        AllowedKeys: List of [Text];
        Token: JsonToken;
        Request: JsonObject;
        BinText: Text;
        ZoneText: Text;
        ItemText: Text;
        BinPresent: Boolean;
        ZonePresent: Boolean;
        ItemPresent: Boolean;
        FormatLbl: Label 'getBinContent must be an object.', Comment = 'is-IS=getBinContent verður að vera hlutur.';
        MissingLbl: Label 'getBinContent needs binCode or zoneCode.', Comment = 'is-IS=getBinContent þarf binCode eða zoneCode.';
        MissingNextStepLbl: Label 'Send getBinContent with binCode or zoneCode, and optionally itemNo.', Comment = 'is-IS=Sendu getBinContent með binCode eða zoneCode og valfrjálst itemNo.';
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table, %2 = value, is-IS=%1 %2 fannst ekki.';
    begin
        RequestJson.Get('getBinContent', Token);
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'getBinContent', '', 'object', FormatNextStepLbl);
            exit;
        end;
        Request := Token.AsObject();
        AllowedKeys.AddRange('binCode', 'zoneCode', 'itemNo');
        Values.RefuseUnknownKeys(Request, AllowedKeys, Argument, 'getBinContent', -1);
        Context.ReadText(Request, 'binCode', MaxStrLen(Bin.Code), Argument, BinText, BinPresent, 'getBinContent.binCode');
        Context.ReadText(Request, 'zoneCode', MaxStrLen(Zone.Code), Argument, ZoneText, ZonePresent, 'getBinContent.zoneCode');
        Context.ReadText(Request, 'itemNo', MaxStrLen(Item."No."), Argument, ItemText, ItemPresent, 'getBinContent.itemNo');
        if not BinPresent and not ZonePresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'getBinContent.binCode', '', '', MissingNextStepLbl);
            exit;
        end;
        BinText := UpperCase(BinText);
        ZoneText := UpperCase(ZoneText);
        ItemText := UpperCase(ItemText);
        if BinPresent then
            if not Bin.Get(LocationCode, CopyStr(BinText, 1, MaxStrLen(Bin.Code))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), BinText), 'getBinContent.binCode', BinText, '', NotFoundNextStepLbl)
            else
                CheckBinNotBlocked(Argument, Bin, false, 'getBinContent.binCode');
        if ZonePresent then
            if not Zone.Get(LocationCode, CopyStr(ZoneText, 1, MaxStrLen(Zone.Code))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Zone.TableCaption(), ZoneText), 'getBinContent.zoneCode', ZoneText, '', NotFoundNextStepLbl);
        if ItemPresent then
            if not Item.Get(CopyStr(ItemText, 1, MaxStrLen(Item."No."))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemText), 'getBinContent.itemNo', ItemText, '', NotFoundNextStepLbl);
        Payload.Add('getBinCode', BinText);
        Payload.Add('getZoneCode', ZoneText);
        Payload.Add('getItemNo', ItemText);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; IsPick: Boolean)
    var
        Values: Codeunit "Whse Msg Values ori";
        AllowedKeys: List of [Text];
    begin
        AllowedKeys.AddRange('locationCode', 'lines', 'release', 'createActivity', 'assignedUserId', 'sortingMethod');
        if IsPick then
            AllowedKeys.AddRange('toZoneCode', 'toBinCode', 'dueDate')
        else
            AllowedKeys.AddRange('fromZoneCode', 'fromBinCode', 'getBinContent');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
    end;

    /// <summary>Creates the internal put-away from the validated payload. Runs inside Codeunit.Run, so any error rolls everything back.</summary>
    /// <param name="Payload">The validated payload.</param>
    /// <param name="Result">Receives the document number and the activity number.</param>
    internal procedure CreatePutAway(Payload: JsonObject; var Result: JsonObject)
    var
        Header: Record "Whse. Internal Put-away Header";
        Line: Record "Whse. Internal Put-away Line";
        ActivityHeader: Record "Warehouse Activity Header";
        CreateDocument: Report "Whse.-Source - Create Document";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Release: Codeunit "Whse. Int. Put-away Release";
        ActivityOption: Option " ","Put-away",Pick,Movement,"Invt. Put-away","Invt. Pick","Invt. Movement";
        NothingErr: Label 'The internal put-away has no lines.', Comment = 'is-IS=Innri frágangurinn hefur engar línur.';
        NoActivityErr: Label 'Business Central created no put-away from the internal put-away.', Comment = 'is-IS=Business Central stofnaði engan frágang úr innri frágangnum.';
    begin
        Header.Init();
        Header.SetHideValidationDialog(true);
        Header.Insert(true);
        Context.SetPendingDocument(Header."No.");
        Header.Validate("Location Code", CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(Header."Location Code")));
        if Values.TextValue(Payload, 'zoneCode') <> '' then
            Header.Validate("From Zone Code", CopyStr(Values.TextValue(Payload, 'zoneCode'), 1, MaxStrLen(Header."From Zone Code")));
        if Values.TextValue(Payload, 'binCode') <> '' then
            Header.Validate("From Bin Code", CopyStr(Values.TextValue(Payload, 'binCode'), 1, MaxStrLen(Header."From Bin Code")));
        Header.Modify(true);
        if Payload.Contains('getBinCode') then
            GetBinContent(Header, Payload)
        else
            InsertPutAwayLines(Header, Values.ArrayValue(Payload, 'lines'));
        Line.SetRange("No.", Header."No.");
        if Line.IsEmpty() then
            Error(NothingErr);
        if Values.BooleanValue(Payload, 'release') then begin
            Release.Release(Header);
            Header.Get(Header."No.");
        end;
        Result.Add('documentNo', Header."No.");
        if not Values.BooleanValue(Payload, 'createActivity') then
            exit;
        CreateDocument.SetWhseInternalPutAway(Header);
        CreateDocument.Initialize(CopyStr(Values.TextValue(Payload, 'assignedUserId'), 1, 50), SortingMethod(Values.TextValue(Payload, 'sortingMethod')), false, false, false);
        CreateDocument.SetHideValidationDialog(true);
        CreateDocument.UseRequestPage(false);
        CreateDocument.RunModal();
        CreateDocument.GetActivityHeader(ActivityHeader, ActivityOption::"Put-away");
        if ActivityHeader."No." = '' then
            Error(NoActivityErr);
        Result.Add('activityNo', ActivityHeader."No.");
    end;

    /// <summary>Creates the internal pick from the validated payload. Runs inside Codeunit.Run, so any error rolls everything back.</summary>
    /// <param name="Payload">The validated payload.</param>
    /// <param name="Result">Receives the document number and the activity number.</param>
    internal procedure CreatePick(Payload: JsonObject; var Result: JsonObject)
    var
        Header: Record "Whse. Internal Pick Header";
        Line: Record "Whse. Internal Pick Line";
        ActivityHeader: Record "Warehouse Activity Header";
        TakeLine: Record "Warehouse Activity Line";
        CreateDocument: Report "Whse.-Source - Create Document";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Release: Codeunit "Whse. Internal Pick Release";
        ActivityOption: Option " ","Put-away",Pick,Movement,"Invt. Put-away","Invt. Pick","Invt. Movement";
        NothingErr: Label 'The internal pick has no lines.', Comment = 'is-IS=Innri tínslan hefur engar línur.';
        NoActivityErr: Label 'Business Central created no pick from the internal pick.', Comment = 'is-IS=Business Central stofnaði enga tínslu úr innri tínslunni.';
        ShortErr: Label 'Only %1 of the %2 asked for, in the base unit, is available to pick. Nothing was written.', Comment = '%1 = quantity available, %2 = quantity asked, is-IS=Aðeins %1 af þeim %2 sem beðið var um, í grunneiningu, er tiltækt til tínslu. Ekkert var skrifað.';
    begin
        Header.Init();
        Header.SetHideValidationDialog(true);
        Header.Insert(true);
        Context.SetPendingDocument(Header."No.");
        Header.Validate("Location Code", CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(Header."Location Code")));
        if Values.TextValue(Payload, 'zoneCode') <> '' then
            Header.Validate("To Zone Code", CopyStr(Values.TextValue(Payload, 'zoneCode'), 1, MaxStrLen(Header."To Zone Code")));
        if Values.TextValue(Payload, 'binCode') <> '' then
            Header.Validate("To Bin Code", CopyStr(Values.TextValue(Payload, 'binCode'), 1, MaxStrLen(Header."To Bin Code")));
        if Payload.Contains('dueDate') then
            Header.Validate("Due Date", Values.DateValue(Payload, 'dueDate'));
        Header.Modify(true);
        InsertPickLines(Header, Values.ArrayValue(Payload, 'lines'));
        Line.SetRange("No.", Header."No.");
        if Line.IsEmpty() then
            Error(NothingErr);
        if Values.BooleanValue(Payload, 'release') then begin
            Release.Release(Header);
            Header.Get(Header."No.");
        end;
        Result.Add('documentNo', Header."No.");
        if not Values.BooleanValue(Payload, 'createActivity') then
            exit;
        Line.FindSet();
        CreateDocument.SetWhseInternalPickLine(Line, CopyStr(Values.TextValue(Payload, 'assignedUserId'), 1, 50));
        CreateDocument.Initialize(CopyStr(Values.TextValue(Payload, 'assignedUserId'), 1, 50), SortingMethod(Values.TextValue(Payload, 'sortingMethod')), false, false, false);
        CreateDocument.SetHideValidationDialog(true);
        CreateDocument.UseRequestPage(false);
        CreateDocument.RunModal();
        CreateDocument.GetActivityHeader(ActivityHeader, ActivityOption::Pick);
        if ActivityHeader."No." = '' then
            Error(NoActivityErr);
        // Business Central creates a partial pick when stock is short. The type promises all or nothing, so a short pick rolls everything back.
        Line.SetRange("No.", Header."No.");
        Line.CalcSums("Qty. (Base)");
        TakeLine.SetRange("Activity Type", ActivityHeader.Type);
        TakeLine.SetRange("No.", ActivityHeader."No.");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        TakeLine.CalcSums("Qty. (Base)");
        if TakeLine."Qty. (Base)" < Line."Qty. (Base)" then
            Error(ShortErr, Format(TakeLine."Qty. (Base)", 0, 9), Format(Line."Qty. (Base)", 0, 9));
        Result.Add('activityNo', ActivityHeader."No.");
    end;

    local procedure SortingMethod(SortingText: Text): Enum "Whse. Activity Sorting Method"
    var
        Context: Codeunit "Whse Write Context ori";
        Method: Enum "Whse. Activity Sorting Method";
        Name: Text;
        Position: Integer;
    begin
        if SortingText = '' then
            exit(Method::None);
        foreach Name in Method.Names() do begin
            Position += 1;
            if Context.SameName(SortingText, Name) then
                exit(Enum::"Whse. Activity Sorting Method".FromInteger(Method.Ordinals().Get(Position)));
        end;
        exit(Method::None);
    end;

    local procedure GetBinContent(Header: Record "Whse. Internal Put-away Header"; Payload: JsonObject)
    var
        BinContent: Record "Bin Content";
        DummyWorksheetLine: Record "Whse. Worksheet Line";
        GetBinContentReport: Report "Whse. Get Bin Content";
        Values: Codeunit "Whse Msg Values ori";
    begin
        BinContent.SetRange("Location Code", Header."Location Code");
        if Values.TextValue(Payload, 'getBinCode') <> '' then
            BinContent.SetRange("Bin Code", Values.TextValue(Payload, 'getBinCode'));
        if Values.TextValue(Payload, 'getZoneCode') <> '' then
            BinContent.SetRange("Zone Code", Values.TextValue(Payload, 'getZoneCode'));
        if Values.TextValue(Payload, 'getItemNo') <> '' then
            BinContent.SetRange("Item No.", Values.TextValue(Payload, 'getItemNo'));
        GetBinContentReport.SetTableView(BinContent);
        GetBinContentReport.SetParameters(DummyWorksheetLine, Header, "Warehouse Destination Type 2"::WhseInternalPutawayHeader);
        GetBinContentReport.UseRequestPage(false);
        GetBinContentReport.RunModal();
    end;

    local procedure InsertPutAwayLines(Header: Record "Whse. Internal Put-away Header"; Lines: JsonArray)
    var
        Line: Record "Whse. Internal Put-away Line";
        Values: Codeunit "Whse Msg Values ori";
        Token: JsonToken;
        LineObject: JsonObject;
        LineNo: Integer;
    begin
        foreach Token in Lines do begin
            LineObject := Token.AsObject();
            LineNo += 10000;
            Line.Init();
            Line."No." := Header."No.";
            Line."Line No." := LineNo;
            Line.SetHideValidationDialog(true);
            Line.Validate("Location Code", Header."Location Code");
            Line.Validate("Item No.", CopyStr(Values.TextValue(LineObject, 'itemNo'), 1, MaxStrLen(Line."Item No.")));
            if Values.TextValue(LineObject, 'variantCode') <> '' then
                Line.Validate("Variant Code", CopyStr(Values.TextValue(LineObject, 'variantCode'), 1, MaxStrLen(Line."Variant Code")));
            Line.Validate("Unit of Measure Code", CopyStr(Values.TextValue(LineObject, 'unitOfMeasureCode'), 1, MaxStrLen(Line."Unit of Measure Code")));
            Line.Validate("From Bin Code", CopyStr(Values.TextValue(LineObject, 'binCode'), 1, MaxStrLen(Line."From Bin Code")));
            Line.Validate(Quantity, Values.DecimalValue(LineObject, 'quantity'));
            Line.Insert(true);
            InsertTracking(Database::"Whse. Internal Put-away Line", Line."No.", Line."Line No.", Line."Location Code", Line."Item No.", Line."Variant Code", Line."Qty. per Unit of Measure", Line."Qty. (Base)", LineObject);
        end;
    end;

    local procedure InsertPickLines(Header: Record "Whse. Internal Pick Header"; Lines: JsonArray)
    var
        Line: Record "Whse. Internal Pick Line";
        Values: Codeunit "Whse Msg Values ori";
        Token: JsonToken;
        LineObject: JsonObject;
        LineNo: Integer;
    begin
        foreach Token in Lines do begin
            LineObject := Token.AsObject();
            LineNo += 10000;
            Line.Init();
            Line."No." := Header."No.";
            Line."Line No." := LineNo;
            Line.SetHideValidationDialog(true);
            Line.Validate("Location Code", Header."Location Code");
            if Header."To Zone Code" <> '' then
                Line.Validate("To Zone Code", Header."To Zone Code");
            if Header."To Bin Code" <> '' then
                Line.Validate("To Bin Code", Header."To Bin Code");
            if Header."Due Date" <> 0D then
                Line.Validate("Due Date", Header."Due Date");
            Line.Validate("Item No.", CopyStr(Values.TextValue(LineObject, 'itemNo'), 1, MaxStrLen(Line."Item No.")));
            if Values.TextValue(LineObject, 'variantCode') <> '' then
                Line.Validate("Variant Code", CopyStr(Values.TextValue(LineObject, 'variantCode'), 1, MaxStrLen(Line."Variant Code")));
            Line.Validate("Unit of Measure Code", CopyStr(Values.TextValue(LineObject, 'unitOfMeasureCode'), 1, MaxStrLen(Line."Unit of Measure Code")));
            Line.Validate(Quantity, Values.DecimalValue(LineObject, 'quantity'));
            Line.Insert(true);
            InsertTracking(Database::"Whse. Internal Pick Line", Line."No.", Line."Line No.", Line."Location Code", Line."Item No.", Line."Variant Code", Line."Qty. per Unit of Measure", Line."Qty. (Base)", LineObject);
        end;
    end;

    local procedure InsertTracking(SourceType: Integer; DocumentNo: Code[20]; LineNo: Integer; LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; QtyPerUnit: Decimal; QtyBase: Decimal; LineObject: JsonObject)
    var
        TrackingLine: Record "Whse. Item Tracking Line";
        Values: Codeunit "Whse Msg Values ori";
        EntryNo: Integer;
    begin
        if (Values.TextValue(LineObject, 'lotNo') = '') and (Values.TextValue(LineObject, 'serialNo') = '') and (Values.TextValue(LineObject, 'packageNo') = '') then
            exit;
        if TrackingLine.FindLast() then
            EntryNo := TrackingLine."Entry No.";
        TrackingLine.Init();
        TrackingLine."Entry No." := EntryNo + 1;
        TrackingLine."Source Type" := SourceType;
        TrackingLine."Source ID" := DocumentNo;
        TrackingLine."Source Ref. No." := LineNo;
        TrackingLine."Location Code" := LocationCode;
        TrackingLine."Item No." := ItemNo;
        TrackingLine."Variant Code" := VariantCode;
        TrackingLine."Qty. per Unit of Measure" := QtyPerUnit;
        TrackingLine."Lot No." := CopyStr(Values.TextValue(LineObject, 'lotNo'), 1, MaxStrLen(TrackingLine."Lot No."));
        TrackingLine."Serial No." := CopyStr(Values.TextValue(LineObject, 'serialNo'), 1, MaxStrLen(TrackingLine."Serial No."));
        TrackingLine."Package No." := CopyStr(Values.TextValue(LineObject, 'packageNo'), 1, MaxStrLen(TrackingLine."Package No."));
        TrackingLine.Validate("Quantity (Base)", QtyBase);
        TrackingLine.Validate("Qty. to Handle (Base)", QtyBase);
        TrackingLine.Insert(true);
    end;

    /// <summary>Writes the success response for a created internal document.</summary>
    /// <param name="Argument">The message argument.</param>
    /// <param name="Result">The result from the write.</param>
    /// <param name="IsPick">True for the internal pick.</param>
    internal procedure WriteResponse(var Argument: Record "Message Argument ori"; Result: JsonObject; IsPick: Boolean)
    var
        PutAwayHeader: Record "Whse. Internal Put-away Header";
        PickHeader: Record "Whse. Internal Pick Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Values: Codeunit "Whse Msg Values ori";
        ResponseJson: JsonObject;
        Lines: JsonArray;
        DocumentNo: Code[20];
        ActivityNo: Code[20];
        MissingResultErr: Label 'The internal document was created but its number was not returned.', Comment = 'is-IS=Innra skjalið var stofnað en númer þess skilaði sér ekki.';
    begin
        DocumentNo := CopyStr(Values.TextValue(Result, 'documentNo'), 1, MaxStrLen(DocumentNo));
        ResponseJson.Add('status', 'Success');
        if IsPick then begin
            if not PickHeader.Get(DocumentNo) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'internalDocumentNo', DocumentNo, '', RefusedNextStepLbl);
                exit;
            end;
            ResponseJson.Add('internalDocumentNo', PickHeader."No.");
            ResponseJson.Add('systemId', Format(PickHeader.SystemId, 0, 4).ToLower());
            ResponseJson.Add('locationCode', PickHeader."Location Code");
            ResponseJson.Add('documentStatus', Format(PickHeader.Status));
            PickLinesJson(PickHeader."No.", Lines);
            ActivityHeader.Type := ActivityHeader.Type::Pick;
        end else begin
            if not PutAwayHeader.Get(DocumentNo) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'internalDocumentNo', DocumentNo, '', RefusedNextStepLbl);
                exit;
            end;
            ResponseJson.Add('internalDocumentNo', PutAwayHeader."No.");
            ResponseJson.Add('systemId', Format(PutAwayHeader.SystemId, 0, 4).ToLower());
            ResponseJson.Add('locationCode', PutAwayHeader."Location Code");
            ResponseJson.Add('documentStatus', Format(PutAwayHeader.Status));
            PutAwayLinesJson(PutAwayHeader."No.", Lines);
            ActivityHeader.Type := ActivityHeader.Type::"Put-away";
        end;
        ResponseJson.Add('lineCount', Lines.Count());
        ResponseJson.Add('lines', Lines);
        ActivityNo := CopyStr(Values.TextValue(Result, 'activityNo'), 1, MaxStrLen(ActivityNo));
        if ActivityNo <> '' then
            if ActivityHeader.Get(ActivityHeader.Type, ActivityNo) then begin
                ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
                ActivityLine.SetRange("No.", ActivityHeader."No.");
                ResponseJson.Add('activityType', Format(ActivityHeader.Type));
                ResponseJson.Add('activityNo', ActivityHeader."No.");
                ResponseJson.Add('activitySystemId', Format(ActivityHeader.SystemId, 0, 4).ToLower());
                ResponseJson.Add('totalLines', ActivityLine.Count());
            end;
        Argument.SetResponseJson(ResponseJson);
    end;

    local procedure PutAwayLinesJson(DocumentNo: Code[20]; var Lines: JsonArray)
    var
        Line: Record "Whse. Internal Put-away Line";
        LineJson: JsonObject;
    begin
        Line.SetRange("No.", DocumentNo);
        if Line.FindSet() then
            repeat
                Clear(LineJson);
                LineJson.Add('lineNo', Line."Line No.");
                LineJson.Add('itemNo', Line."Item No.");
                LineJson.Add('variantCode', Line."Variant Code");
                LineJson.Add('unitOfMeasureCode', Line."Unit of Measure Code");
                LineJson.Add('quantity', Line.Quantity);
                LineJson.Add('fromZoneCode', Line."From Zone Code");
                LineJson.Add('fromBinCode', Line."From Bin Code");
                Lines.Add(LineJson);
            until Line.Next() = 0;
    end;

    local procedure PickLinesJson(DocumentNo: Code[20]; var Lines: JsonArray)
    var
        Line: Record "Whse. Internal Pick Line";
        LineJson: JsonObject;
    begin
        Line.SetRange("No.", DocumentNo);
        if Line.FindSet() then
            repeat
                Clear(LineJson);
                LineJson.Add('lineNo', Line."Line No.");
                LineJson.Add('itemNo', Line."Item No.");
                LineJson.Add('variantCode', Line."Variant Code");
                LineJson.Add('unitOfMeasureCode', Line."Unit of Measure Code");
                LineJson.Add('quantity', Line.Quantity);
                LineJson.Add('toZoneCode', Line."To Zone Code");
                LineJson.Add('toBinCode', Line."To Bin Code");
                Lines.Add(LineJson);
            until Line.Next() = 0;
    end;

    /// <summary>
    /// Removes an internal document, and any activity made from it, that Business Central committed before the call failed,
    /// so a refused call leaves nothing behind (#106).
    /// </summary>
    /// <param name="IsPick">True for the internal pick.</param>
    internal procedure RemovePendingDocument(IsPick: Boolean)
    var
        PutAwayHeader: Record "Whse. Internal Put-away Header";
        PickHeader: Record "Whse. Internal Pick Header";
        ActivityLine: Record "Warehouse Activity Line";
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Write Context ori";
        PutAwayRelease: Codeunit "Whse. Int. Put-away Release";
        PickRelease: Codeunit "Whse. Internal Pick Release";
        DocumentNo: Code[20];
    begin
        if not Context.TryGetPendingDocument(DocumentNo) then
            exit;
        if IsPick then
            ActivityLine.SetRange("Whse. Document Type", ActivityLine."Whse. Document Type"::"Internal Pick")
        else
            ActivityLine.SetRange("Whse. Document Type", ActivityLine."Whse. Document Type"::"Internal Put-away");
        ActivityLine.SetRange("Whse. Document No.", DocumentNo);
        if ActivityLine.FindFirst() then
            if ActivityHeader.Get(ActivityLine."Activity Type", ActivityLine."No.") then
                ActivityHeader.Delete(true);
        if IsPick then begin
            if not PickHeader.Get(DocumentNo) then
                exit;
            if PickHeader.Status = PickHeader.Status::Released then
                PickRelease.Reopen(PickHeader);
            PickHeader.Get(DocumentNo);
            PickHeader.Delete(true);
        end else begin
            if not PutAwayHeader.Get(DocumentNo) then
                exit;
            if PutAwayHeader.Status = PutAwayHeader.Status::Released then
                PutAwayRelease.Reopen(PutAwayHeader);
            PutAwayHeader.Get(DocumentNo);
            PutAwayHeader.Delete(true);
        end;
    end;

    /// <summary>Returns the refusal next step used when Business Central rejects the internal document.</summary>
    /// <returns>The next step.</returns>
    internal procedure RefusedNextStep(): Text
    begin
        exit(RefusedNextStepLbl);
    end;
}
