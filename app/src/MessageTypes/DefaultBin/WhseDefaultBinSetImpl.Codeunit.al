namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.DefaultBin.Set.
/// Bin Content does not clear the previous default on its own. CheckDefaultBin raises when another
/// default already exists, so this type clears that row before Validate(Default).
/// </summary>
codeunit 10078420 "Whse DefaultBin Set Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        LocationCode: Code[10];
        ItemNo: Code[20];
        VariantCode: Code[10];
        PreviousBinCode: Code[20];
        MissingPayloadErr: Label 'The default bin payload was empty.', Comment = 'is-IS=Gögnin fyrir sjálfgefið hólf voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        ItemNo := CopyStr(TextValue(Payload, 'itemNo'), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(TextValue(Payload, 'variantCode'), 1, MaxStrLen(VariantCode));
        PreviousBinCode := CopyStr(TextValue(Payload, 'previousBinCode'), 1, MaxStrLen(PreviousBinCode));
        ClearPreviousDefault(LocationCode, ItemNo, VariantCode, PreviousBinCode);
        SetDefault(Payload);
    end;

    /// <summary>Returns whether the caller can set a default bin.</summary>
    /// <returns>True when the caller can write Bin Content and read the records the write needs.</returns>
    procedure IsEnabled(): Boolean
    var
        BinContent: Record "Bin Content";
        Bin: Record Bin;
        Item: Record Item;
        Location: Record Location;
    begin
        exit(BinContent.WritePermission() and BinContent.ReadPermission() and Bin.ReadPermission() and Item.ReadPermission() and Location.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The Bin Content table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Bin Content");
    end;

    /// <summary>Returns a short description of Warehouse.DefaultBin.Set.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Sets the default bin for an item at a location.', Comment = 'is-IS=Setur sjálfgefið hólf fyrir vöru á staðsetningu.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'default bin, item default bin, bin content, set default, warehouse default, fixed bin', Comment = 'is-IS=sjálfgefið hólf, sjálfgefið vöruhólf, innihald hólfs, setja sjálfgefið, sjálfgefið vöruhús, fast hólf';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Sets Default on bin content through field validation and clears the previous default first. A second call for the same bin changes nothing.', Comment = 'is-IS=Setur Default á innihald hólfs með sannprófun reits og hreinsar fyrra sjálfgefið hólf fyrst. Annað kall fyrir sama hólf breytir engu.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('location code');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A location code selects the same location as locationCode. Do not send a different location in both places.', true);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The location of the item and bin.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode, data.itemNo, data.binCode', 'codes', 'Location, item and bin. Variant and unit of measure are optional.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Location code. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', true, 'Item number.'));
        Parameters.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Item variant. Omit it for the blank variant.'));
        Parameters.Add(ContractMgt.Parameter('unitOfMeasureCode', 'string', false, 'Item unit of measure. Omit it to use the item base unit of measure.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', true, 'Bin that becomes the default.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('changed', 'boolean', 'False when that bin was already the default and nothing was written.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        Fields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        Fields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        Fields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure code used on the bin content.'));
        Fields.Add(ContractMgt.ResponseField('binCode', 'string', 'Default bin code.'));
        Fields.Add(ContractMgt.ResponseField('previousBinCode', 'string', 'Previous default bin, or blank when there was none.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
        NotFoundWhenLbl: Label 'The item, location, bin or variant does not exist.', Comment = 'is-IS=Varan, staðsetningin, hólfið eða afbrigðið er ekki til.';
        NotFoundNextStepLbl: Label 'Check with Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu með Warehouse.Bin.Get.';
        NoBinsWhenLbl: Label 'The location has no bins. The parameter is locationCode.', Comment = 'is-IS=Staðsetningin hefur engin hólf. Færibreytan er locationCode.';
        PreconditionWhenLbl: Label 'The bin type on a directed location does not allow put-away and pick, or the bin has no zone.', Comment = 'is-IS=Hólfategundin á beinu vöruhúsi leyfir ekki frágang og tínslu, eða hólfið er ekki á svæði.';
        PreconditionNextStepLbl: Label 'Choose a bin whose bin type allows it.', Comment = 'is-IS=Veldu hólf þar sem hólfategundin leyfir það.';
        ManyWhenLbl: Label 'More than one value failed validation. errors[] lists each one with its own code.', Comment = 'is-IS=Fleiri en eitt gildi stóðst ekki prófun. errors telur hvert þeirra upp með eigin kóða.';
        ManyNextStepLbl: Label 'Correct every listed value and send the request again. Nothing was written.', Comment = 'is-IS=Leiðréttu öll gildin sem eru talin upp og sendu beiðnina aftur. Ekkert var skrifað.';
        BlockWhenLbl: Label 'The bin blocks movement.', Comment = 'is-IS=Hólfið hindrar flutning.';
        BlockNextStepLbl: Label 'Unblock the bin or choose another.', Comment = 'is-IS=Aflæstu hólfinu eða veldu annað.';
        UnitWhenLbl: Label 'The unit of measure does not exist for the item.', Comment = 'is-IS=Mælieiningin er ekki til fyrir vöruna.';
        UnitNextStepLbl: Label 'Send a unit of measure that exists for the item.', Comment = 'is-IS=Sendu mælieiningu sem er til fyrir vöruna.';
        MissingWhenLbl: Label 'locationCode, itemNo or binCode was not sent.', Comment = 'is-IS=locationCode, itemNo eða binCode var ekki sent.';
        MissingNextStepLbl: Label 'Send locationCode, itemNo and binCode.', Comment = 'is-IS=Sendu locationCode, itemNo og binCode.';
        FormatWhenLbl: Label 'A code was not text.', Comment = 'is-IS=Kóði var ekki texti.';
        FormatNextStepLbl: Label 'Send text for locationCode, itemNo, variantCode, unitOfMeasureCode and binCode.', Comment = 'is-IS=Sendu texta fyrir locationCode, itemNo, variantCode, unitOfMeasureCode og binCode.';
        UnknownWhenLbl: Label 'The request contains a key this type does not accept.', Comment = 'is-IS=Beiðnin inniheldur lykil sem þessi gerð tekur ekki við.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
        ConflictWhenLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        DeniedWhenLbl: Label 'The caller cannot write bin content.', Comment = 'is-IS=Sá sem kallar getur ekki skrifað innihald hólfs.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        PlatformWhenLbl: Label 'Business Central rejected the default bin.', Comment = 'is-IS=Business Central hafnaði sjálfgefna hólfinu.';
        PlatformNextStepLbl: Label 'Read the returned text and correct the item, bin or unit of measure.', Comment = 'is-IS=Lestu textann sem kom til baka og leiðréttu vöruna, hólfið eða mælieininguna.';
    begin
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::RecordNotFound, NotFoundWhenLbl, NotFoundNextStepLbl);
        Entry.Add('nextStep', NotFoundNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, NoBinsWhenLbl, NoBinsNextStep());
        Entry.Add('nextStep', NoBinsNextStep());
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, PreconditionWhenLbl, PreconditionNextStepLbl);
        Entry.Add('nextStep', PreconditionNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, BlockWhenLbl, BlockNextStepLbl);
        Entry.Add('nextStep', BlockNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, UnitWhenLbl, UnitNextStepLbl);
        Entry.Add('nextStep', UnitNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::MissingParameter, MissingWhenLbl, MissingNextStepLbl);
        Entry.Add('nextStep', MissingNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, FormatWhenLbl, FormatNextStepLbl);
        Entry.Add('nextStep', FormatNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::UnknownParameter, UnknownWhenLbl, UnknownNextStepLbl);
        Entry.Add('nextStep', UnknownNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictWhenLbl, ConflictNextStepLbl);
        Entry.Add('nextStep', ConflictNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::PermissionDenied, DeniedWhenLbl, DeniedNextStepLbl);
        Entry.Add('nextStep', DeniedNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::BusinessCentralError, PlatformWhenLbl, PlatformNextStepLbl);
        Entry.Add('nextStep', PlatformNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::MultipleErrors, ManyWhenLbl, ManyNextStepLbl);
        Entry.Add('nextStep', ManyNextStepLbl);
        Errors.Add(Entry);
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Sets the default bin for an item. Sending the bin that is already the default writes nothing.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Get', 'Use it to read the bins at the location before choosing one.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the bin content after the default is set.'));
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Set the default bin',
            '{"locationCode":"MAIN","itemNo":"ITEM","binCode":"A-01"}',
            '{"status":"Success","changed":true,"locationCode":"MAIN","itemNo":"ITEM","variantCode":"","unitOfMeasureCode":"PCS","binCode":"A-01","previousBinCode":""}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Sets the default bin for an item at a location and reports the previous default bin.', Comment = 'is-IS=Setur sjálfgefið hólf fyrir vöru á staðsetningu og skilar fyrra sjálfgefna hólfinu.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := '';
        exit(false);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Sets the default bin, or answers changed false when it is already the default.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        DeniedLbl: Label 'You do not have permission to set the default bin.', Comment = 'is-IS=Þú hefur ekki heimild til að setja sjálfgefið hólf.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
    begin
        Context.Reset();
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        RefuseUnknownKeys(RequestJson, Argument);
        if not TryBuildPayload(RequestJson, Argument, Payload) then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if UnchangedDefault(Payload) then begin
            WriteResult(Argument, Payload, false);
            exit;
        end;
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse DefaultBin Set Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse DefaultBin Set Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        Context.Reset();
        WriteResult(Argument, Payload, true);
    end;

    local procedure TryBuildPayload(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var Payload: JsonObject): Boolean
    var
        Location: Record Location;
        Item: Record Item;
        ItemVariant: Record "Item Variant";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        Bin: Record Bin;
        BinType: Record "Bin Type";
        LocationText: Text;
        ItemText: Text;
        VariantText: Text;
        UnitText: Text;
        BinText: Text;
        LocationPresent: Boolean;
        ItemPresent: Boolean;
        VariantPresent: Boolean;
        UnitPresent: Boolean;
        BinPresent: Boolean;
        LocationCode: Code[10];
        ItemNo: Code[20];
        VariantCode: Code[10];
        UnitCode: Code[10];
        BinCode: Code[20];
        PreviousBinCode: Code[20];
        SubjectText: Text;
        LocationKey: Text;
        MissingLbl: Label '%1 is required.', Comment = '%1 = parameter, is-IS=%1 er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode, itemNo and binCode.', Comment = 'is-IS=Sendu locationCode, itemNo og binCode.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = record, %2 = code, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check with Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu með Warehouse.Bin.Get.';
        NoBinsLbl: Label 'Location %1 has no bins.', Comment = '%1 = location, is-IS=Staðsetning %1 hefur engin hólf.';
        PreconditionNextStepLbl: Label 'Choose a bin whose bin type allows it.', Comment = 'is-IS=Veldu hólf þar sem hólfategundin leyfir það.';
        BlockLbl: Label 'Bin %1 blocks movement.', Comment = '%1 = bin, is-IS=Hólf %1 hindrar flutning.';
        BlockNextStepLbl: Label 'Unblock the bin or choose another.', Comment = 'is-IS=Aflæstu hólfinu eða veldu annað.';
        UnitLbl: Label 'Unit of measure %1 does not exist for item %2.', Comment = '%1 = unit, %2 = item, is-IS=Mælieining %1 er ekki til fyrir vöru %2.';
        UnitNextStepLbl: Label 'Send a unit of measure that exists for the item.', Comment = 'is-IS=Sendu mælieiningu sem er til fyrir vöruna.';
        BinTypeLbl: Label 'Bin type %1 does not allow put-away and pick.', Comment = '%1 = bin type, is-IS=Hólfategund %1 leyfir ekki frágang og tínslu.';
    begin
        Clear(Payload);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not ReadText(RequestJson, 'locationCode', MaxStrLen(Location.Code), Argument, LocationText, LocationPresent) then
            exit(false);
        if not ReadText(RequestJson, 'itemNo', MaxStrLen(Item."No."), Argument, ItemText, ItemPresent) then
            exit(false);
        if not ReadText(RequestJson, 'variantCode', MaxStrLen(ItemVariant.Code), Argument, VariantText, VariantPresent) then
            exit(false);
        if not ReadText(RequestJson, 'unitOfMeasureCode', MaxStrLen(ItemUnitOfMeasure.Code), Argument, UnitText, UnitPresent) then
            exit(false);
        if not ReadText(RequestJson, 'binCode', MaxStrLen(Bin.Code), Argument, BinText, BinPresent) then
            exit(false);
        if LocationPresent and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationText)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        LocationKey := 'locationCode';
        if not LocationPresent then begin
            LocationText := SubjectText;
            LocationKey := 'subject';
        end;
        if LocationText = '' then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'locationCode'), 'locationCode', '', '', MissingNextStepLbl);
        if not ItemPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'itemNo'), 'itemNo', '', '', MissingNextStepLbl);
        if not BinPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'binCode'), 'binCode', '', '', MissingNextStepLbl);
        if Argument.HasCollectedErrors() then
            exit(false);
        LocationCode := CopyStr(UpperCase(LocationText), 1, MaxStrLen(LocationCode));
        ItemNo := CopyStr(UpperCase(ItemText), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(UpperCase(VariantText), 1, MaxStrLen(VariantCode));
        BinCode := CopyStr(UpperCase(BinText), 1, MaxStrLen(BinCode));
        Location.SetLoadFields(Code, "Directed Put-away and Pick");
        if not Location.Get(LocationCode) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Location.TableCaption(), LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
            exit(false);
        end;
        Item.SetLoadFields("No.", "Base Unit of Measure");
        if not Item.Get(ItemNo) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemNo), 'itemNo', ItemNo, '', NotFoundNextStepLbl);
            exit(false);
        end;
        Bin.SetRange("Location Code", LocationCode);
        if Bin.IsEmpty() then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoBinsLbl, LocationCode), LocationKey, LocationText, '', NoBinsNextStep());
            exit(false);
        end;
        Bin.Reset();
        Bin.SetLoadFields(Code, "Block Movement", "Bin Type Code", "Zone Code");
        if not Bin.Get(LocationCode, BinCode) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), BinCode), 'binCode', BinCode, '', NotFoundNextStepLbl);
            exit(false);
        end;
        if Bin."Block Movement" <> Bin."Block Movement"::" " then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(BlockLbl, BinCode), 'binCode', BinCode, '', BlockNextStepLbl);
            exit(false);
        end;
        if Location."Directed Put-away and Pick" then begin
            BinType.SetLoadFields(Code, "Put Away", Pick);
            if (Bin."Bin Type Code" = '') or (not BinType.Get(Bin."Bin Type Code")) or (not BinType."Put Away") or (not BinType.Pick) then begin
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BinTypeLbl, Bin."Bin Type Code"), 'binCode', BinCode, '', PreconditionNextStepLbl);
                exit(false);
            end;
            if Bin."Zone Code" = '' then begin
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BinTypeLbl, Bin."Bin Type Code"), 'binCode', BinCode, '', PreconditionNextStepLbl);
                exit(false);
            end;
        end;
        if VariantCode <> '' then begin
            ItemVariant.SetLoadFields(Code);
            if not ItemVariant.Get(ItemNo, VariantCode) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemVariant.TableCaption(), VariantCode), 'variantCode', VariantCode, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        if UnitPresent then begin
            UnitCode := CopyStr(UpperCase(UnitText), 1, MaxStrLen(UnitCode));
            ItemUnitOfMeasure.SetLoadFields(Code);
            if not ItemUnitOfMeasure.Get(ItemNo, UnitCode) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(UnitLbl, UnitCode, ItemNo), 'unitOfMeasureCode', UnitCode, '', UnitNextStepLbl);
                exit(false);
            end;
        end else
            UnitCode := Item."Base Unit of Measure";
        if UnitCode = '' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(UnitLbl, UnitCode, ItemNo), 'unitOfMeasureCode', '', '', UnitNextStepLbl);
            exit(false);
        end;
        PreviousBinCode := FindPreviousBin(LocationCode, ItemNo, VariantCode);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('itemNo', ItemNo);
        Payload.Add('variantCode', VariantCode);
        Payload.Add('unitOfMeasureCode', UnitCode);
        Payload.Add('binCode', BinCode);
        Payload.Add('previousBinCode', PreviousBinCode);
        exit(true);
    end;

    local procedure FindPreviousBin(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]): Code[20]
    var
        BinContent: Record "Bin Content";
    begin
        BinContent.SetLoadFields("Bin Code");
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", VariantCode);
        BinContent.SetRange(Default, true);
        if BinContent.FindFirst() then
            exit(BinContent."Bin Code");
        exit('');
    end;

    local procedure UnchangedDefault(Payload: JsonObject): Boolean
    begin
        exit((TextValue(Payload, 'previousBinCode') <> '') and (TextValue(Payload, 'previousBinCode') = TextValue(Payload, 'binCode')));
    end;

    local procedure WriteResult(var Argument: Record "Message Argument ori"; Payload: JsonObject; Changed: Boolean)
    var
        ResponseJson: JsonObject;
    begin
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('changed', Changed);
        ResponseJson.Add('locationCode', TextValue(Payload, 'locationCode'));
        ResponseJson.Add('itemNo', TextValue(Payload, 'itemNo'));
        ResponseJson.Add('variantCode', TextValue(Payload, 'variantCode'));
        ResponseJson.Add('unitOfMeasureCode', TextValue(Payload, 'unitOfMeasureCode'));
        ResponseJson.Add('binCode', TextValue(Payload, 'binCode'));
        ResponseJson.Add('previousBinCode', TextValue(Payload, 'previousBinCode'));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure TextValue(Payload: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if Payload.Get(KeyName, Token) and Token.IsValue() and (not Token.AsValue().IsNull()) then
            exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['locationCode', 'itemNo', 'variantCode', 'unitOfMeasureCode', 'binCode']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure ReadText(RequestJson: JsonObject; KeyName: Text; MaxLength: Integer; var Argument: Record "Message Argument ori"; var Value: Text; var Present: Boolean): Boolean
    var
        Token: JsonToken;
        ValueText: Text;
        FormatLbl: Label 'Parameter %1 must be text.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera texti.';
        FormatNextStepLbl: Label 'Send text for locationCode, itemNo, variantCode, unitOfMeasureCode and binCode.', Comment = 'is-IS=Sendu texta fyrir locationCode, itemNo, variantCode, unitOfMeasureCode og binCode.';
        TooLongLbl: Label 'Parameter %1 is longer than %2 characters.', Comment = '%1 = parameter, %2 = maximum, is-IS=Færibreytan %1 er lengri en %2 stafir.';
        TooLongNextStepLbl: Label 'Send a shorter value.', Comment = 'is-IS=Sendu styttra gildi.';
    begin
        Clear(Value);
        Present := false;
        if not RequestJson.Get(KeyName, Token) then
            exit(true);
        if not Token.IsValue() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), KeyName, '', 'text', FormatNextStepLbl);
            exit(false);
        end;
        if Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'text' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), KeyName, ReceivedText(Token), 'text', FormatNextStepLbl);
            exit(false);
        end;
        ValueText := Token.AsValue().AsText();
        if ValueText = '' then
            exit(true);
        if StrLen(ValueText) > MaxLength then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(TooLongLbl, KeyName, MaxLength), KeyName, CopyStr(ValueText, 1, 80), 'text', TooLongNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := ValueText;
        exit(true);
    end;

    local procedure ReceivedText(Token: JsonToken): Text
    begin
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        if ValueKind(Token) in ['text', 'number', 'boolean'] then
            exit(CopyStr(Token.AsValue().AsText(), 1, 80));
        exit('');
    end;

    local procedure ValueKind(Token: JsonToken): Text
    var
        Written: Text;
    begin
        if not Token.IsValue() then
            exit('complex');
        if Token.AsValue().IsNull() then
            exit('null');
        Token.WriteTo(Written);
        if CopyStr(Written, 1, 1) = '"' then
            exit('text');
        if (Written = 'true') or (Written = 'false') then
            exit('boolean');
        exit('number');
    end;

    local procedure ClearPreviousDefault(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; PreviousBinCode: Code[20])
    var
        BinContent: Record "Bin Content";
    begin
        if PreviousBinCode = '' then
            exit;
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", VariantCode);
        BinContent.SetRange(Default, true);
        if BinContent.FindSet(true) then
            repeat
                BinContent.Validate(Default, false);
                BinContent.Modify(true);
            until BinContent.Next() = 0;
    end;

    local procedure SetDefault(Payload: JsonObject)
    var
        BinContent: Record "Bin Content";
        LocationCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        VariantCode: Code[10];
        UnitOfMeasureCode: Code[10];
    begin
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        BinCode := CopyStr(TextValue(Payload, 'binCode'), 1, MaxStrLen(BinCode));
        ItemNo := CopyStr(TextValue(Payload, 'itemNo'), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(TextValue(Payload, 'variantCode'), 1, MaxStrLen(VariantCode));
        UnitOfMeasureCode := CopyStr(TextValue(Payload, 'unitOfMeasureCode'), 1, MaxStrLen(UnitOfMeasureCode));
        if not BinContent.Get(LocationCode, BinCode, ItemNo, VariantCode, UnitOfMeasureCode) then
            InsertBinContent(BinContent, LocationCode, BinCode, ItemNo, VariantCode, UnitOfMeasureCode);
        BinContent.Validate(Default, true);
        BinContent.Modify(true);
    end;

    local procedure InsertBinContent(var BinContent: Record "Bin Content"; LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UnitOfMeasureCode: Code[10])
    begin
        BinContent.Init();
        BinContent.Validate("Location Code", LocationCode);
        BinContent.Validate("Bin Code", BinCode);
        BinContent.SetUpNewLine();
        BinContent.Validate("Item No.", ItemNo);
        if VariantCode <> '' then
            BinContent.Validate("Variant Code", VariantCode);
        if BinContent."Unit of Measure Code" <> UnitOfMeasureCode then
            BinContent.Validate("Unit of Measure Code", UnitOfMeasureCode);
        BinContent.Validate(Fixed, true);
        BinContent.Insert(true);
    end;

    local procedure NoBinsNextStep(): Text
    var
        NextStepLbl: Label 'Create bins at the location with Warehouse.Bin.Create; the location needs Bin Mandatory turned on.', Comment = 'is-IS=Stofnaðu hólf á staðsetningunni með Warehouse.Bin.Create; kveikja þarf á skyldunotkun hólfa á staðsetningunni.';
    begin
        exit(NextStepLbl);
    end;
}