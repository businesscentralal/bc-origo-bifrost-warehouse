namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Bin.Create. Bins are validated and then inserted inside Codeunit.Run.
/// Empty is not written: Business Central initializes it and keeps it non-editable.
/// </summary>
codeunit 10078419 "Whse Bin Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        Bins: JsonArray;
        BinToken: JsonToken;
        MissingPayloadErr: Label 'The bin create payload was empty.', Comment = 'is-IS=Gögnin til að stofna hólf voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        if not Payload.Get('bins', BinToken) then
            Error(MissingPayloadErr);
        Bins := BinToken.AsArray();
        foreach BinToken in Bins do
            InsertBin(Payload, BinToken.AsObject());
    end;

    /// <summary>Returns whether the caller can create bins.</summary>
    /// <returns>True when the caller can write Bin and read Location.</returns>
    procedure IsEnabled(): Boolean
    var
        Bin: Record Bin;
        Location: Record Location;
    begin
        exit(Bin.WritePermission() and Location.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The Bin table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::Bin);
    end;

    /// <summary>Returns a short description of Warehouse.Bin.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates one or more bins at a bin-mandatory location.', Comment = 'is-IS=Stofnar eitt eða fleiri hólf á staðsetningu þar sem hólf eru skyld.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create bin, new bin, bin setup, add bin, warehouse bin, location bin', Comment = 'is-IS=stofna hólf, nýtt hólf, uppsetning hólfs, bæta við hólfi, vöruhúsahólf, hólf staðsetningar';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes bins through field validation. A failed bin writes nothing. Use Warehouse.Bin.Get to read bins afterwards.', Comment = 'is-IS=Skrifar hólf með sannprófun reita. Hólf sem mistekst skrifar ekkert. Notaðu Warehouse.Bin.Get til að lesa hólf á eftir.';
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
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The location that receives the bins.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The location that receives the bins.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Location code. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('bins', 'array', true, 'One or more bins to create. All are created, or none.'));
        Parameters.Add(ContractMgt.Parameter('code', 'string', true, 'Bin code, unique at the location.'));
        Parameters.Add(ContractMgt.Parameter('description', 'string', false, 'Bin description.'));
        Parameters.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Zone code. Required on a directed location and refused on a basic location.'));
        Parameters.Add(ContractMgt.Parameter('binTypeCode', 'string', false, 'Bin type code. Required on a directed location and refused on a basic location.'));
        Parameters.Add(ContractMgt.Parameter('ranking', 'integer', false, 'Bin ranking. Defaults to 0.'));
        Parameters.Add(ContractMgt.Parameter('blockMovement', 'string', false, 'Blank, Inbound, Outbound or All.'));
        Parameters.Add(ContractMgt.Parameter('dedicated', 'boolean', false, 'Whether the bin is dedicated. Defaults to false.'));
        Parameters.Add(ContractMgt.Parameter('empty', 'boolean', false, 'Must be omitted or true. A new bin stays empty until stock is posted.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        BinFields: JsonArray;
        Bins: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('count', 'integer', 'Number of bins created.'));
        BinFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        BinFields.Add(ContractMgt.ResponseField('code', 'string', 'Bin code.'));
        BinFields.Add(ContractMgt.ResponseField('description', 'string', 'Bin description.'));
        BinFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone code.'));
        BinFields.Add(ContractMgt.ResponseField('binTypeCode', 'string', 'Bin type code.'));
        BinFields.Add(ContractMgt.ResponseField('ranking', 'integer', 'Bin ranking.'));
        BinFields.Add(ContractMgt.ResponseField('blockMovement', 'string', 'Blank, Inbound, Outbound or All.'));
        BinFields.Add(ContractMgt.ResponseField('dedicated', 'boolean', 'Whether the bin is dedicated.'));
        BinFields.Add(ContractMgt.ResponseField('empty', 'boolean', 'Whether Business Central marks the bin empty.'));
        Bins.Add('name', 'bins');
        Bins.Add('type', 'array');
        Bins.Add('description', 'The bins that were created.');
        Bins.Add('children', BinFields);
        Fields.Add(Bins);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
        BinMandatoryWhenLbl: Label 'The location does not have Bin Mandatory turned on.', Comment = 'is-IS=Staðsetningin er ekki með Bin Mandatory kveikt.';
        BinMandatoryNextStepLbl: Label 'Turn on Bin Mandatory on the location first.', Comment = 'is-IS=Kveiktu fyrst á Bin Mandatory á staðsetningunni.';
        DuplicateWhenLbl: Label 'The bin code already exists at the location.', Comment = 'is-IS=Hólfakóðinn er þegar til á staðsetningunni.';
        DuplicateNextStepLbl: Label 'Read Warehouse.Bin.Get or choose another code.', Comment = 'is-IS=Lestu Warehouse.Bin.Get eða veldu annan kóða.';
        ZoneWhenLbl: Label 'zoneCode or binTypeCode was sent for a basic location, or the code is unknown.', Comment = 'is-IS=zoneCode eða binTypeCode var sent fyrir einfalda staðsetningu, eða kóðinn er óþekktur.';
        ZoneNextStepLbl: Label 'Leave them blank for basic warehouse locations.', Comment = 'is-IS=Skildu þau eftir tóm fyrir einfaldar vöruhúsastaðsetningar.';
        DirectedWhenLbl: Label 'A directed location needs both zoneCode and binTypeCode.', Comment = 'is-IS=Beint vöruhús þarf bæði zoneCode og binTypeCode.';
        DirectedNextStepLbl: Label 'Send zoneCode and binTypeCode for a directed location.', Comment = 'is-IS=Sendu zoneCode og binTypeCode fyrir beint vöruhús.';
        BlockWhenLbl: Label 'blockMovement is not blank, Inbound, Outbound or All.', Comment = 'is-IS=blockMovement er ekki autt, Inbound, Outbound eða All.';
        BlockNextStepLbl: Label 'Use Inbound, Outbound, All, or leave it blank.', Comment = 'is-IS=Notaðu Inbound, Outbound, All, eða skildu það eftir autt.';
        EmptyWhenLbl: Label 'empty was sent as false.', Comment = 'is-IS=empty var sent sem false.';
        EmptyNextStepLbl: Label 'Leave empty out or send true. Business Central keeps a new bin empty until stock is posted.', Comment = 'is-IS=Slepptu empty eða sendu true. Business Central heldur nýju hólfi tómu þar til birgðir eru bókaðar.';
        MissingWhenLbl: Label 'locationCode or the bins array is missing.', Comment = 'is-IS=locationCode eða bins fylkið vantar.';
        MissingNextStepLbl: Label 'Send locationCode and at least one bin.', Comment = 'is-IS=Sendu locationCode og að minnsta kosti eitt hólf.';
        FormatWhenLbl: Label 'A value has the wrong JSON type or is too long.', Comment = 'is-IS=Gildi er af rangri JSON-gerð eða of langt.';
        FormatNextStepLbl: Label 'Send text for codes, an integer for ranking, and true or false for dedicated and empty.', Comment = 'is-IS=Sendu texta fyrir kóða, heiltölu fyrir ranking og true eða false fyrir dedicated og empty.';
        UnknownWhenLbl: Label 'The request contains a key this type does not accept.', Comment = 'is-IS=Beiðnin inniheldur lykil sem þessi gerð tekur ekki við.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
        NotFoundWhenLbl: Label 'The location does not exist.', Comment = 'is-IS=Staðsetningin er ekki til.';
        NotFoundNextStepLbl: Label 'Check the location with the location setup, or read Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu staðsetninguna í uppsetningu staðsetningar, eða lestu Warehouse.Bin.Get.';
        ConflictWhenLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        DeniedWhenLbl: Label 'The caller cannot write bins.', Comment = 'is-IS=Sá sem kallar getur ekki skrifað hólf.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ManyWhenLbl: Label 'More than one bin failed validation.', Comment = 'is-IS=Fleiri en eitt hólf féll á sannprófun.';
        ManyNextStepLbl: Label 'Correct every listed bin and send the request again. Nothing was written.', Comment = 'is-IS=Leiðréttu hvert skráð hólf og sendu beiðnina aftur. Ekkert var skrifað.';
        PlatformWhenLbl: Label 'Business Central rejected the bin.', Comment = 'is-IS=Business Central hafnaði hólfinu.';
        PlatformNextStepLbl: Label 'Read the returned text and correct the bin or the location setup.', Comment = 'is-IS=Lestu textann sem kom til baka og leiðréttu hólfið eða uppsetningu staðsetningar.';
    begin
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, BinMandatoryWhenLbl, BinMandatoryNextStepLbl);
        Entry.Add('nextStep', BinMandatoryNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, DuplicateWhenLbl, DuplicateNextStepLbl);
        Entry.Add('nextStep', DuplicateNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, ZoneWhenLbl, ZoneNextStepLbl);
        Entry.Add('nextStep', ZoneNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, DirectedWhenLbl, DirectedNextStepLbl);
        Entry.Add('nextStep', DirectedNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, BlockWhenLbl, BlockNextStepLbl);
        Entry.Add('nextStep', BlockNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, EmptyWhenLbl, EmptyNextStepLbl);
        Entry.Add('nextStep', EmptyNextStepLbl);
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
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::RecordNotFound, NotFoundWhenLbl, NotFoundNextStepLbl);
        Entry.Add('nextStep', NotFoundNextStepLbl);
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
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::MultipleErrors, ManyWhenLbl, ManyNextStepLbl);
        Entry.Add('nextStep', ManyNextStepLbl);
        Errors.Add(Entry);
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry("Bifrost Error Code ori"::BusinessCentralError, PlatformWhenLbl, PlatformNextStepLbl);
        Entry.Add('nextStep', PlatformNextStepLbl);
        Errors.Add(Entry);
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Creates bins at a location. The same call is not idempotent: a second call with the same code is refused.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Get', 'Use it to read the bins after they are created.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.DefaultBin.Set', 'Use it to mark one of the bins as the default for an item.'));
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
            'Create two bins',
            '{"locationCode":"MAIN","bins":[{"code":"A-01","description":"Aisle A"},{"code":"A-02","description":"Aisle A end","ranking":10,"dedicated":true}]}',
            '{"status":"Success","count":2,"bins":[{"locationCode":"MAIN","code":"A-01","description":"Aisle A","zoneCode":"","binTypeCode":"","ranking":0,"blockMovement":"","dedicated":false,"empty":true},{"locationCode":"MAIN","code":"A-02","description":"Aisle A end","zoneCode":"","binTypeCode":"","ranking":10,"blockMovement":"","dedicated":true,"empty":true}]}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Creates bins at a bin-mandatory location. One failure writes none of the bins.', Comment = 'is-IS=Stofnar hólf á staðsetningu þar sem hólf eru skyld. Ein villa skrifar ekkert af hólfunum.';
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

    /// <summary>Validates the requested bins and inserts them together, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        LocationCode: Code[10];
        DeniedLbl: Label 'You do not have permission to create bins.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna hólf.';
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
        RequestJson := Argument.GetRequestJson();
        RefuseUnknownKeys(RequestJson, Argument);
        if not TryResolveLocation(RequestJson, Argument, LocationCode) then
            LocationCode := '';
        ReadBins(RequestJson, Argument, LocationCode, Payload);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Context.SetPayload(Payload);
        if not Codeunit.Run(Codeunit::"Whse Bin Create Impl ori") then begin
            Context.Reset();
            Argument.RespondWithLastError();
            exit;
        end;
        Context.Reset();
        WriteCreatedBins(Argument, Payload);
    end;

    local procedure ReadBins(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; var Payload: JsonObject)
    var
        Token: JsonToken;
        Bins: JsonArray;
        Planned: JsonArray;
        Seen: List of [Text];
        Index: Integer;
        MissingLbl: Label 'bins must contain at least one bin.', Comment = 'is-IS=bins verður að innihalda að minnsta kosti eitt hólf.';
        MissingNextStepLbl: Label 'Send locationCode and at least one bin.', Comment = 'is-IS=Sendu locationCode og að minnsta kosti eitt hólf.';
        FormatLbl: Label 'bins must be an array of bin objects.', Comment = 'is-IS=bins verður að vera fylki hólfahluta.';
        FormatNextStepLbl: Label 'Send text for codes, an integer for ranking, and true or false for dedicated and empty.', Comment = 'is-IS=Sendu texta fyrir kóða, heiltölu fyrir ranking og true eða false fyrir dedicated og empty.';
    begin
        Clear(Payload);
        if LocationCode <> '' then
            Payload.Add('locationCode', LocationCode);
        if not EnsureBinMandatory(Argument, LocationCode) then
            LocationCode := '';
        if not RequestJson.Get('bins', Token) then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'bins', '', '', MissingNextStepLbl);
            exit;
        end;
        if not Token.IsArray() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'bins', '', 'array', FormatNextStepLbl);
            exit;
        end;
        Bins := Token.AsArray();
        if Bins.Count() = 0 then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'bins', '', '', MissingNextStepLbl);
            exit;
        end;
        for Index := 0 to Bins.Count() - 1 do begin
            Bins.Get(Index, Token);
            ReadOneBin(Token, Index, Argument, LocationCode, Seen, Planned);
        end;
        Payload.Add('bins', Planned);
    end;

    local procedure ReadOneBin(Token: JsonToken; Index: Integer; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; var Seen: List of [Text]; var Planned: JsonArray)
    var
        BinObject: JsonObject;
        PlannedBin: JsonObject;
        CodeText: Text;
        DescriptionText: Text;
        ZoneCode: Text;
        BinTypeCode: Text;
        BlockText: Text;
        CodePresent: Boolean;
        DescriptionPresent: Boolean;
        ZonePresent: Boolean;
        BinTypePresent: Boolean;
        BlockPresent: Boolean;
        Ranking: Integer;
        RankingPresent: Boolean;
        Dedicated: Boolean;
        DedicatedPresent: Boolean;
        EmptyValue: Boolean;
        EmptyPresent: Boolean;
        FormatLbl: Label 'Each bin must be an object.', Comment = 'is-IS=Hvert hólf verður að vera hlutur.';
        FormatNextStepLbl: Label 'Send text for codes, an integer for ranking, and true or false for dedicated and empty.', Comment = 'is-IS=Sendu texta fyrir kóða, heiltölu fyrir ranking og true eða false fyrir dedicated og empty.';
        MissingCodeLbl: Label 'Bin code is required.', Comment = 'is-IS=Hólfakóði er nauðsynlegur.';
        MissingNextStepLbl: Label 'Send locationCode and at least one bin.', Comment = 'is-IS=Sendu locationCode og að minnsta kosti eitt hólf.';
    begin
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, BinParameter(Index, 'code'), '', 'object', FormatNextStepLbl);
            exit;
        end;
        BinObject := Token.AsObject();
        RefuseUnknownBinKeys(BinObject, Index, Argument);
        if ReadText(BinObject, 'code', 20, Argument, CodeText, CodePresent, Index) then
            if not CodePresent then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingCodeLbl, BinParameter(Index, 'code'), '', '', MissingNextStepLbl);
        if not ReadText(BinObject, 'description', 100, Argument, DescriptionText, DescriptionPresent, Index) then
            DescriptionPresent := false;
        if not DescriptionPresent then
            DescriptionText := '';
        ReadText(BinObject, 'zoneCode', 10, Argument, ZoneCode, ZonePresent, Index);
        ReadText(BinObject, 'binTypeCode', 10, Argument, BinTypeCode, BinTypePresent, Index);
        if not ReadInteger(BinObject, 'ranking', Argument, Ranking, RankingPresent, Index) then
            RankingPresent := false;
        if not RankingPresent then
            Ranking := 0;
        ReadText(BinObject, 'blockMovement', 20, Argument, BlockText, BlockPresent, Index);
        ReadBoolean(BinObject, 'dedicated', Argument, Dedicated, DedicatedPresent, Index);
        if not DedicatedPresent then
            Dedicated := false;
        if ReadBoolean(BinObject, 'empty', Argument, EmptyValue, EmptyPresent, Index) then
            if EmptyPresent and (not EmptyValue) then
                AddEmptyRefusal(Argument, Index);
        if BlockPresent then
            if not IsBlockMovement(BlockText) then
                AddBlockRefusal(Argument, Index, BlockText);
        if not BlockPresent then
            BlockText := '';
        if LocationCode <> '' then
            ValidateBinAgainstLocation(Argument, LocationCode, CodeText, CodePresent, ZoneCode, ZonePresent, BinTypeCode, BinTypePresent, Seen, Index);
        if CodePresent then
            if not Seen.Contains(UpperCase(CodeText)) then
                Seen.Add(UpperCase(CodeText));
        if not CodePresent then
            exit;
        PlannedBin.Add('code', UpperCase(CodeText));
        PlannedBin.Add('description', DescriptionText);
        PlannedBin.Add('zoneCode', ZoneCode);
        PlannedBin.Add('binTypeCode', BinTypeCode);
        PlannedBin.Add('ranking', Ranking);
        PlannedBin.Add('blockMovement', BlockText);
        PlannedBin.Add('dedicated', Dedicated);
        Planned.Add(PlannedBin);
    end;

    local procedure ValidateBinAgainstLocation(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; CodeText: Text; CodePresent: Boolean; ZoneCode: Text; ZonePresent: Boolean; BinTypeCode: Text; BinTypePresent: Boolean; Seen: List of [Text]; Index: Integer)
    var
        Location: Record Location;
        Bin: Record Bin;
        DuplicateLbl: Label 'Bin %1 already exists at location %2.', Comment = '%1 = bin code, %2 = location, is-IS=Hólf %1 er þegar til á staðsetningu %2.';
        DuplicateNextStepLbl: Label 'Read Warehouse.Bin.Get or choose another code.', Comment = 'is-IS=Lestu Warehouse.Bin.Get eða veldu annan kóða.';
    begin
        Location.SetLoadFields(Code, "Directed Put-away and Pick");
        if not Location.Get(LocationCode) then
            exit;
        if not Location."Directed Put-away and Pick" then
            RefuseZoneOnBasicLocation(Argument, ZoneCode, ZonePresent, BinTypeCode, BinTypePresent, Index)
        else
            ValidateDirectedZoneAndType(Argument, LocationCode, ZoneCode, ZonePresent, BinTypeCode, BinTypePresent, Index);
        if not CodePresent then
            exit;
        if Seen.Contains(UpperCase(CodeText)) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(DuplicateLbl, CodeText, LocationCode), BinParameter(Index, 'code'), CodeText, '', DuplicateNextStepLbl);
            exit;
        end;
        Bin.SetLoadFields(Code);
        if Bin.Get(LocationCode, CopyStr(UpperCase(CodeText), 1, MaxStrLen(Bin.Code))) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(DuplicateLbl, CodeText, LocationCode), BinParameter(Index, 'code'), CodeText, '', DuplicateNextStepLbl);
    end;

    local procedure EnsureBinMandatory(var Argument: Record "Message Argument ori"; LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        BinMandatoryLbl: Label 'Location %1 does not use bins.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki hólf.';
        BinMandatoryNextStepLbl: Label 'Turn on Bin Mandatory on the location first.', Comment = 'is-IS=Kveiktu fyrst á Bin Mandatory á staðsetningunni.';
    begin
        if LocationCode = '' then
            exit(false);
        Location.SetLoadFields("Bin Mandatory");
        if not Location.Get(LocationCode) then
            exit(false);
        if Location."Bin Mandatory" then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BinMandatoryLbl, LocationCode), 'locationCode', LocationCode, '', BinMandatoryNextStepLbl);
        exit(false);
    end;

    local procedure TryResolveLocation(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        LocationText: Text;
        Present: Boolean;
        SubjectText: Text;
        MissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode and at least one bin.', Comment = 'is-IS=Sendu locationCode og að minnsta kosti eitt hólf.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the location with the location setup, or read Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu staðsetninguna í uppsetningu staðsetningar, eða lestu Warehouse.Bin.Get.';
    begin
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not ReadText(RequestJson, 'locationCode', MaxStrLen(Location.Code), Argument, LocationText, Present, -1) then
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
        LocationCode := CopyStr(LocationText, 1, MaxStrLen(Location.Code));
        Location.SetLoadFields(Code);
        if Location.Get(LocationCode) then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
        Clear(LocationCode);
        exit(false);
    end;

    local procedure WriteCreatedBins(var Argument: Record "Message Argument ori"; Payload: JsonObject)
    var
        Bin: Record Bin;
        ResponseJson: JsonObject;
        BinsJson: JsonArray;
        Result: JsonArray;
        Token: JsonToken;
        BinObject: JsonObject;
        CodeToken: JsonToken;
    begin
        Payload.Get('bins', Token);
        BinsJson := Token.AsArray();
        foreach Token in BinsJson do begin
            BinObject := Token.AsObject();
            BinObject.Get('code', CodeToken);
            Bin.Get(CopyStr(TextOrEmpty(Payload, 'locationCode'), 1, MaxStrLen(Bin."Location Code")), CopyStr(CodeToken.AsValue().AsText(), 1, MaxStrLen(Bin.Code)));
            Result.Add(CreatedBinJson(Bin));
        end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('count', Result.Count());
        ResponseJson.Add('bins', Result);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure CreatedBinJson(Bin: Record Bin) BinResult: JsonObject
    begin
        BinResult.Add('locationCode', Bin."Location Code");
        BinResult.Add('code', Bin.Code);
        BinResult.Add('description', Bin.Description);
        BinResult.Add('zoneCode', Bin."Zone Code");
        BinResult.Add('binTypeCode', Bin."Bin Type Code");
        BinResult.Add('ranking', Bin."Bin Ranking");
        BinResult.Add('blockMovement', BlockMovementText(Bin));
        BinResult.Add('dedicated', Bin.Dedicated);
        BinResult.Add('empty', Bin.Empty);
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

    local procedure TextOrEmpty(Payload: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if Payload.Get(KeyName, Token) and Token.IsValue() and (not Token.AsValue().IsNull()) then
            exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure AddEmptyRefusal(var Argument: Record "Message Argument ori"; Index: Integer)
    var
        EmptyLbl: Label 'A new bin cannot be marked not empty.', Comment = 'is-IS=Nýtt hólf er ekki hægt að merkja sem ekki tómt.';
        EmptyNextStepLbl: Label 'Leave empty out or send true. Business Central keeps a new bin empty until stock is posted.', Comment = 'is-IS=Slepptu empty eða sendu true. Business Central heldur nýju hólfi tómu þar til birgðir eru bókaðar.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, EmptyLbl, BinParameter(Index, 'empty'), 'false', 'true', EmptyNextStepLbl);
    end;

    local procedure AddBlockRefusal(var Argument: Record "Message Argument ori"; Index: Integer; BlockText: Text)
    var
        BlockLbl: Label 'blockMovement %1 is not supported.', Comment = '%1 = value, is-IS=blockMovement %1 er ekki stutt.';
        BlockNextStepLbl: Label 'Use Inbound, Outbound, All, or leave it blank.', Comment = 'is-IS=Notaðu Inbound, Outbound, All, eða skildu það eftir autt.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(BlockLbl, BlockText), BinParameter(Index, 'blockMovement'), BlockText, '', BlockNextStepLbl);
    end;

    local procedure IsBlockMovement(BlockText: Text): Boolean
    var
        Folded: Text;
    begin
        Folded := UpperCase(DelChr(BlockText, '<>', ' '));
        exit(Folded in ['', 'INBOUND', 'OUTBOUND', 'ALL']);
    end;

    local procedure BinParameter(Index: Integer; KeyName: Text): Text
    var
        BinParameterLbl: Label 'bins[%1].%2', Locked = true;
    begin
        if Index < 0 then
            exit(KeyName);
        exit(StrSubstNo(BinParameterLbl, Index, KeyName));
    end;

    local procedure RefuseZoneOnBasicLocation(var Argument: Record "Message Argument ori"; ZoneCode: Text; ZonePresent: Boolean; BinTypeCode: Text; BinTypePresent: Boolean; Index: Integer)
    var
        BasicLbl: Label 'zoneCode and binTypeCode are only used on a directed location.', Comment = 'is-IS=zoneCode og binTypeCode eru aðeins notuð á beinu vöruhúsi.';
        BasicNextStepLbl: Label 'Leave them blank for basic warehouse locations.', Comment = 'is-IS=Skildu þau eftir tóm fyrir einfaldar vöruhúsastaðsetningar.';
    begin
        if (ZonePresent and (ZoneCode <> '')) or (BinTypePresent and (BinTypeCode <> '')) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, BasicLbl, BinParameter(Index, 'zoneCode'), ZoneCode, '', BasicNextStepLbl);
    end;

    local procedure ValidateDirectedZoneAndType(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; ZoneCode: Text; ZonePresent: Boolean; BinTypeCode: Text; BinTypePresent: Boolean; Index: Integer)
    var
        Zone: Record Zone;
        BinType: Record "Bin Type";
        BasicNextStepLbl: Label 'Leave them blank for basic warehouse locations.', Comment = 'is-IS=Skildu þau eftir tóm fyrir einfaldar vöruhúsastaðsetningar.';
        UnknownLbl: Label 'Zone or bin type %1 was not found.', Comment = '%1 = code, is-IS=Svæði eða hólfategund %1 fannst ekki.';
        DirectedLbl: Label 'A directed location needs zoneCode and binTypeCode.', Comment = 'is-IS=Beint vöruhús þarf zoneCode og binTypeCode.';
        DirectedNextStepLbl: Label 'Send zoneCode and binTypeCode for a directed location.', Comment = 'is-IS=Sendu zoneCode og binTypeCode fyrir beint vöruhús.';
    begin
        if (not ZonePresent) or (ZoneCode = '') or (not BinTypePresent) or (BinTypeCode = '') then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, DirectedLbl, BinParameter(Index, 'zoneCode'), '', '', DirectedNextStepLbl);
            exit;
        end;
        Zone.SetLoadFields(Code);
        if not Zone.Get(LocationCode, CopyStr(ZoneCode, 1, MaxStrLen(Zone.Code))) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(UnknownLbl, ZoneCode), BinParameter(Index, 'zoneCode'), ZoneCode, '', BasicNextStepLbl);
        BinType.SetLoadFields(Code);
        if not BinType.Get(CopyStr(BinTypeCode, 1, MaxStrLen(BinType.Code))) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(UnknownLbl, BinTypeCode), BinParameter(Index, 'binTypeCode'), BinTypeCode, '', BasicNextStepLbl);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['locationCode', 'bins']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure RefuseUnknownBinKeys(BinObject: JsonObject; Index: Integer; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in BinObject.Keys() do
            if not IsBinField(KeyName) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), BinParameter(Index, KeyName), KeyName, '', UnknownNextStepLbl);
    end;

    local procedure IsBinField(KeyName: Text): Boolean
    begin
        exit(KeyName in ['code', 'description', 'zoneCode', 'binTypeCode', 'ranking', 'blockMovement', 'dedicated', 'empty']);
    end;

    local procedure ReadText(SourceJson: JsonObject; KeyName: Text; MaxLength: Integer; var Argument: Record "Message Argument ori"; var Value: Text; var Present: Boolean; Index: Integer): Boolean
    var
        Token: JsonToken;
        ValueText: Text;
        FormatLbl: Label 'Parameter %1 must be text.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera texti.';
        FormatNextStepLbl: Label 'Send text for codes, an integer for ranking, and true or false for dedicated and empty.', Comment = 'is-IS=Sendu texta fyrir kóða, heiltölu fyrir ranking og true eða false fyrir dedicated og empty.';
        TooLongLbl: Label 'Parameter %1 is longer than %2 characters.', Comment = '%1 = parameter, %2 = maximum, is-IS=Færibreytan %1 er lengri en %2 stafir.';
        TooLongNextStepLbl: Label 'Send a shorter value.', Comment = 'is-IS=Sendu styttra gildi.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if not Token.IsValue() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), BinParameter(Index, KeyName), '', 'text', FormatNextStepLbl);
            exit(false);
        end;
        if Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'text' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), BinParameter(Index, KeyName), ReceivedText(Token), 'text', FormatNextStepLbl);
            exit(false);
        end;
        ValueText := Token.AsValue().AsText();
        if ValueText = '' then
            exit(true);
        if StrLen(ValueText) > MaxLength then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(TooLongLbl, KeyName, MaxLength), BinParameter(Index, KeyName), CopyStr(ValueText, 1, 80), 'text', TooLongNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := ValueText;
        exit(true);
    end;

    local procedure ReadBoolean(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Boolean; var Present: Boolean; Index: Integer): Boolean
    var
        Token: JsonToken;
        FormatLbl: Label 'Parameter %1 must be true or false.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera true eða false.';
        FormatNextStepLbl: Label 'Send text for codes, an integer for ranking, and true or false for dedicated and empty.', Comment = 'is-IS=Sendu texta fyrir kóða, heiltölu fyrir ranking og true eða false fyrir dedicated og empty.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'boolean' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), BinParameter(Index, KeyName), ReceivedText(Token), 'boolean', FormatNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsBoolean();
        exit(true);
    end;

    local procedure ReadInteger(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Integer; var Present: Boolean; Index: Integer): Boolean
    var
        Token: JsonToken;
        Number: Decimal;
        FormatLbl: Label 'Parameter %1 must be an integer.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera heiltala.';
        FormatNextStepLbl: Label 'Send text for codes, an integer for ranking, and true or false for dedicated and empty.', Comment = 'is-IS=Sendu texta fyrir kóða, heiltölu fyrir ranking og true eða false fyrir dedicated og empty.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'number' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), BinParameter(Index, KeyName), ReceivedText(Token), 'integer', FormatNextStepLbl);
            exit(false);
        end;
        Number := Token.AsValue().AsDecimal();
        if Number <> Round(Number, 1) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), BinParameter(Index, KeyName), ReceivedText(Token), 'integer', FormatNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsInteger();
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

    local procedure InsertBin(Payload: JsonObject; BinObject: JsonObject)
    var
        Bin: Record Bin;
        LocationToken: JsonToken;
        Token: JsonToken;
    begin
        Bin.Init();
        Payload.Get('locationCode', LocationToken);
        Bin.Validate("Location Code", CopyStr(LocationToken.AsValue().AsText(), 1, MaxStrLen(Bin."Location Code")));
        BinObject.Get('code', Token);
        Bin.Validate(Code, CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin.Code)));
        if BinObject.Get('description', Token) then
            if Token.AsValue().AsText() <> '' then
                Bin.Validate(Description, CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin.Description)));
        if BinObject.Get('zoneCode', Token) then
            if Token.AsValue().AsText() <> '' then
                Bin.Validate("Zone Code", CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin."Zone Code")));
        if BinObject.Get('binTypeCode', Token) then
            if Token.AsValue().AsText() <> '' then
                Bin.Validate("Bin Type Code", CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin."Bin Type Code")));
        if BinObject.Get('ranking', Token) then
            Bin.Validate("Bin Ranking", Token.AsValue().AsInteger());
        if BinObject.Get('blockMovement', Token) then
            ValidateBlockMovement(Bin, Token.AsValue().AsText());
        if BinObject.Get('dedicated', Token) then
            if Token.AsValue().AsBoolean() then
                Bin.Validate(Dedicated, true);
        Bin.Insert(true);
    end;

    local procedure ValidateBlockMovement(var Bin: Record Bin; BlockText: Text)
    begin
        case UpperCase(BlockText) of
            'INBOUND':
                Bin.Validate("Block Movement", Bin."Block Movement"::Inbound);
            'OUTBOUND':
                Bin.Validate("Block Movement", Bin."Block Movement"::Outbound);
            'ALL':
                Bin.Validate("Block Movement", Bin."Block Movement"::All);
            else
                Bin.Validate("Block Movement", Bin."Block Movement"::" ");
        end;
    end;
}
