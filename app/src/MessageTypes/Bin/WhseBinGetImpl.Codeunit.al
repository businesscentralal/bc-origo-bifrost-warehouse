namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Bin.Get as a paged read of bin master data.
/// The story text called this an inbound write. It is an outbound read, like Warehouse.BinContent.Get.
/// </summary>
codeunit 10078418 "Whse Bin Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read bins.</summary>
    /// <returns>True when the caller has read permission on Bin.</returns>
    procedure IsEnabled(): Boolean
    var
        Bin: Record Bin;
    begin
        exit(Bin.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The Bin table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::Bin);
    end;

    /// <summary>Returns a short description of Warehouse.Bin.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reads bins at a location, with optional bin content.', Comment = 'is-IS=Les hólf á staðsetningu, með valfrjálsu innihaldi hólfs.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'bin, bin master, location bin, warehouse bin, bin list, empty bin', Comment = 'is-IS=hólf, hólfaskrá, hólf staðsetningar, vöruhúsahólf, hólfalisti, tómt hólf';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Reads paged bins at one location. Use Warehouse.Bin.Create to add bins and Warehouse.BinContent.Get for item quantities.', Comment = 'is-IS=Lesaðgangur. Les blaðsíðuskipt hólf á einni staðsetningu. Notaðu Warehouse.Bin.Create til að bæta við hólfum og Warehouse.BinContent.Get fyrir magn vöru.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('location code');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A location code selects the same location as locationCode. Do not send a different location in both places.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The location whose bins are read.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The location whose bins are read.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddPagingParameters(Parameters);
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Location code. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Return only this bin code.'));
        Parameters.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Return only bins in this zone.'));
        Parameters.Add(ContractMgt.Parameter('binTypeCode', 'string', false, 'Return only bins of this bin type.'));
        Parameters.Add(ContractMgt.Parameter('empty', 'boolean', false, 'Return only bins whose Empty field matches.'));
        Parameters.Add(ContractMgt.Parameter('includeContent', 'boolean', false, 'When true, each bin includes content with item, variant, unit of measure and quantity.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        ResultFields: JsonArray;
        ContentFields: JsonArray;
        Result: JsonObject;
        Content: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('noOfRecords', 'integer', 'Total number of matching bins before paging.'));
        Fields.Add(ContractMgt.ResponseField('skip', 'integer', 'Number of bins skipped.'));
        Fields.Add(ContractMgt.ResponseField('take', 'integer', 'Maximum number of bins requested.'));
        ResultFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        ResultFields.Add(ContractMgt.ResponseField('code', 'string', 'Bin code.'));
        ResultFields.Add(ContractMgt.ResponseField('description', 'string', 'Bin description.'));
        ResultFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone code.'));
        ResultFields.Add(ContractMgt.ResponseField('binTypeCode', 'string', 'Bin type code.'));
        ResultFields.Add(ContractMgt.ResponseField('ranking', 'integer', 'Bin ranking.'));
        ResultFields.Add(ContractMgt.ResponseField('blockMovement', 'string', 'Blank, Inbound, Outbound or All.'));
        ResultFields.Add(ContractMgt.ResponseField('dedicated', 'boolean', 'Whether the bin is dedicated.'));
        ResultFields.Add(ContractMgt.ResponseField('empty', 'boolean', 'Whether Business Central marks the bin empty.'));
        ContentFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        ContentFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        ContentFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure code.'));
        ContentFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity in the bin.'));
        Content.Add('name', 'content');
        Content.Add('type', 'array');
        Content.Add('description', 'Included when includeContent is true.');
        Content.Add('children', ContentFields);
        ResultFields.Add(Content);
        Result.Add('name', 'result');
        Result.Add('type', 'array');
        Result.Add('description', 'The paged bins.');
        Result.Add('children', ResultFields);
        Fields.Add(Result);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
        MissingWhenLbl: Label 'locationCode was not sent and subject is empty.', Comment = 'is-IS=locationCode var ekki sent og subject er tómt.';
        MissingNextStepLbl: Label 'Send locationCode or the location code as the subject.', Comment = 'is-IS=Sendu locationCode eða kóða staðsetningarinnar sem subject.';
        FormatWhenLbl: Label 'A code was not text, or empty or includeContent was not true or false.', Comment = 'is-IS=Kóði var ekki texti, eða empty eða includeContent var ekki true eða false.';
        FormatNextStepLbl: Label 'Send text for codes and true or false for empty and includeContent.', Comment = 'is-IS=Sendu texta fyrir kóða og true eða false fyrir empty og includeContent.';
        UnknownWhenLbl: Label 'The request contains a key this type does not accept.', Comment = 'is-IS=Beiðnin inniheldur lykil sem þessi gerð tekur ekki við.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
        NotFoundWhenLbl: Label 'The location does not exist.', Comment = 'is-IS=Staðsetningin er ekki til.';
        NotFoundNextStepLbl: Label 'Check the location code and try again.', Comment = 'is-IS=Athugaðu kóða staðsetningarinnar og reyndu aftur.';
        ConflictWhenLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        DeniedWhenLbl: Label 'The caller cannot read bins or, when includeContent is true, bin content.', Comment = 'is-IS=Sá sem kallar getur ekki lesið hólf, eða innihald hólfs þegar includeContent er true.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
    begin
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
        Parts.AddPagingErrors(Errors, true);
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads bins and, when requested, bin content. Changes nothing.', 'BIFROST Whse - Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Create', 'Use it to create bins at a bin-mandatory location.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read item quantities in bins without the bin master fields.'));
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
            'Read one bin and its content',
            '{"locationCode":"MAIN","binCode":"A-01","includeContent":true}',
            '{"status":"Success","noOfRecords":1,"skip":0,"take":100,"result":[{"locationCode":"MAIN","code":"A-01","description":"Aisle A","zoneCode":"","binTypeCode":"","ranking":0,"blockMovement":"","dedicated":false,"empty":true,"content":[{"itemNo":"ITEM","variantCode":"","unitOfMeasureCode":"PCS","quantity":0}]}]}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Read-only, paged access to bins at one location, with optional content.', Comment = 'is-IS=Lesaðgangur, blaðsíðuskiptur, að hólfum á einni staðsetningu, með valfrjálsu innihaldi.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'One location is read per call: send locationCode or the location code as the subject, and it must exist. Sending different locations in both places is refused. A location that has no bins (for example one that is not bin mandatory) is Success with an empty result. ' +
            'binCode, zoneCode and binTypeCode are exact filters; empty selects bins whose Empty field is true or false, and Business Central maintains that field from the warehouse entries. Empty text and null values are ignored, so they do not filter. ' +
            'A key this type does not know is refused as UnknownParameter, and all request problems, including a bad skip or take, are answered together in one answer. ' +
            'includeContent adds every bin content row of each bin, also rows with quantity 0 such as an empty fixed bin, and needs read permission on bin content as well as on bins. Bins and content of other locations are not touched. ' +
            'blockMovement is blank, Inbound, Outbound or All. Content here lists item, variant, unit of measure and quantity only; use Warehouse.BinContent.Get to filter on an item across locations or to see zone and bin type per row.';
        exit(true);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Reads matching bins and returns a paged JSON result.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        LocationCode: Code[10];
        BinCode: Text;
        ZoneCode: Text;
        BinTypeCode: Text;
        EmptyValue: Boolean;
        IncludeContent: Boolean;
        EmptyPresent: Boolean;
        IncludePresent: Boolean;
        Skip: Integer;
        Take: Integer;
        DeniedLbl: Label 'You do not have permission to read bins.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa hólf.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
        ProblemsLbl: Label 'The bin query was refused.', Comment = 'is-IS=Fyrirspurn um hólf var hafnað.';
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
        if not ResolveLocationCode(RequestJson, Argument, LocationCode) then
            LocationCode := ''
        else
            CheckLocationExists(LocationCode, Argument);
        ReadText(RequestJson, 'binCode', 20, Argument, BinCode, EmptyPresent);
        EmptyPresent := false;
        ReadText(RequestJson, 'zoneCode', 10, Argument, ZoneCode, EmptyPresent);
        EmptyPresent := false;
        ReadText(RequestJson, 'binTypeCode', 10, Argument, BinTypeCode, EmptyPresent);
        if not ReadBoolean(RequestJson, 'empty', Argument, EmptyValue, EmptyPresent) then
            EmptyPresent := false;
        if not ReadBoolean(RequestJson, 'includeContent', Argument, IncludeContent, IncludePresent) then
            IncludePresent := false;
        if not IncludePresent then
            IncludeContent := false;
        NotePagingKeys(RequestJson);
        // Every problem of the request is answered together, a bad skip or take included.
        if not Context.RespondOrReadPaging(RequestJson, Argument, ProblemsLbl, Skip, Take) then
            exit;
        if IncludeContent then
            if not CanReadContent(Argument) then
                exit;
        WriteBinPage(Argument, LocationCode, BinCode, ZoneCode, BinTypeCode, EmptyPresent, EmptyValue, IncludeContent, Skip, Take);
    end;

    local procedure WriteBinPage(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; BinCode: Text; ZoneCode: Text; BinTypeCode: Text; EmptyPresent: Boolean; EmptyValue: Boolean; IncludeContent: Boolean; Skip: Integer; Take: Integer)
    var
        Bin: Record Bin;
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        NoOfRecords: Integer;
    begin
        Bin.ReadIsolation := IsolationLevel::ReadCommitted;
        Bin.SetLoadFields("Location Code", Code, Description, "Zone Code", "Bin Type Code", "Bin Ranking", "Block Movement", Dedicated, Empty);
        Bin.SetRange("Location Code", LocationCode);
        if BinCode <> '' then
            Bin.SetRange(Code, CopyStr(BinCode, 1, MaxStrLen(Bin.Code)));
        if ZoneCode <> '' then
            Bin.SetRange("Zone Code", CopyStr(ZoneCode, 1, MaxStrLen(Bin."Zone Code")));
        if BinTypeCode <> '' then
            Bin.SetRange("Bin Type Code", CopyStr(BinTypeCode, 1, MaxStrLen(Bin."Bin Type Code")));
        if EmptyPresent then
            Bin.SetRange(Empty, EmptyValue);
        NoOfRecords := Bin.Count();
        if Skip < NoOfRecords then
            if Bin.FindSet() then begin
                if Skip > 0 then
                    Bin.Next(Skip);
                repeat
                    ResultArray.Add(BinJson(Bin, IncludeContent));
                    if ResultArray.Count() >= Take then
                        break;
                until Bin.Next() = 0;
            end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('noOfRecords', NoOfRecords);
        ResponseJson.Add('skip', Skip);
        ResponseJson.Add('take', Take);
        ResponseJson.Add('result', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure BinJson(Bin: Record Bin; IncludeContent: Boolean) BinResult: JsonObject
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
        if IncludeContent then
            BinResult.Add('content', ContentJson(Bin));
    end;

    local procedure ContentJson(Bin: Record Bin) ContentArray: JsonArray
    var
        BinContent: Record "Bin Content";
        ContentJsonObject: JsonObject;
    begin
        BinContent.ReadIsolation := IsolationLevel::ReadCommitted;
        BinContent.SetRange("Location Code", Bin."Location Code");
        BinContent.SetRange("Bin Code", Bin.Code);
        BinContent.SetLoadFields("Item No.", "Variant Code", "Unit of Measure Code");
        BinContent.SetAutoCalcFields(Quantity);
        if BinContent.FindSet() then
            repeat
                Clear(ContentJsonObject);
                ContentJsonObject.Add('itemNo', BinContent."Item No.");
                ContentJsonObject.Add('variantCode', BinContent."Variant Code");
                ContentJsonObject.Add('unitOfMeasureCode', BinContent."Unit of Measure Code");
                ContentJsonObject.Add('quantity', BinContent.Quantity);
                ContentArray.Add(ContentJsonObject);
            until BinContent.Next() = 0;
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

    local procedure CheckLocationExists(LocationCode: Code[10]; var Argument: Record "Message Argument ori")
    var
        Location: Record Location;
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the location code and try again.', Comment = 'is-IS=Athugaðu kóða staðsetningar og reyndu aftur.';
    begin
        Location.SetLoadFields(Code);
        if not Location.Get(LocationCode) then
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
    end;

    local procedure CanReadContent(var Argument: Record "Message Argument ori"): Boolean
    var
        BinContent: Record "Bin Content";
        DeniedLbl: Label 'You do not have permission to read bin content.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa innihald hólfs.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
    begin
        if BinContent.ReadPermission() then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, 'includeContent', '', '', DeniedNextStepLbl);
        exit(false);
    end;

    local procedure ResolveLocationCode(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]): Boolean
    var
        LocationText: Text;
        Present: Boolean;
        SubjectText: Text;
        MissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode or the location code as the subject.', Comment = 'is-IS=Sendu locationCode eða kóða staðsetningar sem subject.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
    begin
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, Present) then
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
        if StrLen(LocationText) > MaxStrLen(LocationCode) then
            exit(false);
        LocationCode := CopyStr(LocationText, 1, MaxStrLen(LocationCode));
        exit(true);
    end;

    local procedure NotePagingKeys(RequestJson: JsonObject)
    var
        HasSkip: Boolean;
        HasTake: Boolean;
    begin
        HasSkip := RequestJson.Contains('skip');
        HasTake := RequestJson.Contains('take');
        if HasSkip or HasTake then
            exit;
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not IsAllowedKey(KeyName) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure IsAllowedKey(KeyName: Text): Boolean
    begin
        exit(KeyName in ['locationCode', 'binCode', 'zoneCode', 'binTypeCode', 'empty', 'includeContent', 'skip', 'take']);
    end;

    local procedure ReadText(RequestJson: JsonObject; KeyName: Text; MaxLength: Integer; var Argument: Record "Message Argument ori"; var Value: Text; var Present: Boolean): Boolean
    var
        Token: JsonToken;
        ValueText: Text;
        Received: Text;
        FormatLbl: Label 'Parameter %1 must be text.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera texti.';
        FormatNextStepLbl: Label 'Send text for codes and true or false for empty and includeContent.', Comment = 'is-IS=Sendu texta fyrir kóða og true eða false fyrir empty og includeContent.';
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
            Received := ReceivedText(Token);
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), KeyName, Received, 'text', FormatNextStepLbl);
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

    local procedure ReadBoolean(RequestJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Boolean; var Present: Boolean): Boolean
    var
        Token: JsonToken;
        FormatLbl: Label 'Parameter %1 must be true or false.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera true eða false.';
        FormatNextStepLbl: Label 'Send text for codes and true or false for empty and includeContent.', Comment = 'is-IS=Sendu texta fyrir kóða og true eða false fyrir empty og includeContent.';
    begin
        Clear(Value);
        Present := false;
        if not RequestJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'boolean' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), KeyName, ReceivedText(Token), 'boolean', FormatNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsBoolean();
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
}
