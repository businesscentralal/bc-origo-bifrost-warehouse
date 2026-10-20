namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.RegisteredActivity.Get: a paged read of registered picks, put-aways or movements,
/// by number or by filters, optionally with their lines.
/// </summary>
codeunit 10078437 "Whse RegActivity Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read registered warehouse activities.</summary>
    /// <returns>True when the caller can read the registered activity header and line tables.</returns>
    procedure IsEnabled(): Boolean
    var
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        RegisteredLine: Record "Registered Whse. Activity Line";
    begin
        exit(RegisteredHeader.ReadPermission() and RegisteredLine.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The registered warehouse activity header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Registered Whse. Activity Hdr.");
    end;

    /// <summary>Returns a short description of Warehouse.RegisteredActivity.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reads registered picks, put-aways or movements, optionally with lines.', Comment = 'is-IS=Les skráðar tínslur, frágang eða tilfærslur, valfrjálst með línum.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'registered pick, registered put-away, registered movement, what was picked, where was it put away, warehouse activity history', Comment = 'is-IS=skráð tínsla, skráður frágangur, skráð tilfærsla, hvað var tínt, hvar var gengið frá, saga vöruhúsavirkni';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Reads registered picks, put-aways or movements by number or by location, source number and registering date, paged.', Comment = 'is-IS=Lesaðgangur. Les skráðar tínslur, frágang eða tilfærslur eftir númeri eða eftir staðsetningu, númeri upprunaskjals og skráningardegi, blaðsíðuskipt.';
    begin
        exit(SelectionLbl);
    end;

    /// <summary>Returns the subject envelope.</summary>
    /// <param name="Envelope">Receives the envelope.</param>
    /// <returns>True when the envelope is used.</returns>
    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('activity no.');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A registered activity number selects the same activity as no. Do not send a different number in both places.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'activity no.', 'The number of the registered pick, put-away or movement.'));
        Target.Add(ContractMgt.TargetEntry('data.no', 'activity no.', 'The number of the registered pick, put-away or movement.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parameters.Add(ContractMgt.Parameter('activityType', 'string', true, 'Pick, PutAway or Movement.'));
        Parameters.Add(ContractMgt.Parameter('no', 'string', false, 'Registered activity number. Leave it out to search with filters.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location code.'));
        Parameters.Add(ContractMgt.Parameter('sourceNo', 'string', false, 'Source document number on any line of the registered activity.'));
        Parameters.Add(ContractMgt.Parameter('registeringDateFrom', 'date', false, 'First registering date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('registeringDateTo', 'date', false, 'Last registering date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('includeLines', 'boolean', false, 'Return the lines of each activity. Defaults to false.'));
        Parts.AddPagingParameters(Parameters);
        exit(true);
    end;

    /// <summary>Returns the response chapter.</summary>
    /// <param name="Response">Receives the response.</param>
    /// <returns>True when a response is declared.</returns>
    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('activityType', 'string', 'Pick, Put-away or Movement.'));
        Fields.Add(ContractMgt.ResponseField('noOfRecords', 'integer', 'Number of matching registered activities before paging.'));
        Fields.Add(ContractMgt.ResponseField('skip', 'integer', 'Records skipped.'));
        Fields.Add(ContractMgt.ResponseField('take', 'integer', 'Page size.'));
        Fields.Add(ContractMgt.ResponseField('result', 'array', 'Registered activities: activityType, no, systemId, locationCode, registeringDate, whseActivityNo, assignedUserId, and lines when includeLines is true (lineNo, actionType, itemNo, variantCode, description, quantity, unitOfMeasureCode, zoneCode, binCode, sourceDocument, sourceNo, sourceLineNo, whseDocumentType, whseDocumentNo, lotNo, serialNo).'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'activityType is missing.', 'Send activityType Pick, PutAway or Movement.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'activityType is not Pick, PutAway or Movement, or the registering date range ends before it starts.', 'Use one of the values listed in the help.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The named registered activity does not exist.', 'Search with filters instead of a no.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and no name different activities.', 'Send one number: subject or no.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or a date is not YYYY-MM-DD.', 'Send text for codes, true or false for includeLines, and dates as YYYY-MM-DD.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot read registered warehouse activities.', 'Ask an administrator to assign BIFROST Whse - Read ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads registered picks, put-aways or movements. Nothing is written.', 'BIFROST Whse - Read ori');
        exit(true);
    end;

    /// <summary>Returns the metering chapter.</summary>
    /// <param name="Metering">Receives the metering.</param>
    /// <returns>False. This type is not metered.</returns>
    procedure GetMetering(var Metering: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns related message types.</summary>
    /// <param name="Related">Receives the related types.</param>
    /// <returns>True when related types are declared.</returns>
    procedure GetRelated(var Related: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to read open picks, put-aways and movements.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'It registers the picks this type reads.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Register', 'It registers the put-aways this type reads.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Movement.Register', 'It registers the movements this type reads.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. This read has no workflow chapter.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns an example request and response.</summary>
    /// <param name="Examples">Receives the examples.</param>
    /// <returns>True when an example is declared.</returns>
    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Registered picks at WHITE in October 2026',
            '{"activityType":"Pick","locationCode":"WHITE","registeringDateFrom":"2026-10-01","registeringDateTo":"2026-10-31"}',
            '{"status":"Success","activityType":"Pick","noOfRecords":1,"skip":0,"take":20,"result":[{"activityType":"Pick","no":"R_PI000001","systemId":"6f1c1d2e-0000-0000-0000-000000000003","locationCode":"WHITE","registeringDate":"2026-10-19","whseActivityNo":"PI000001","assignedUserId":""}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Reads registered picks, put-aways or movements (activityType Pick, PutAway or Movement) by number, or by location, source document number and registering date range, paged with take and skip. includeLines adds the lines. A number that does not exist is refused; filters that match nothing answer success with an empty list. Nothing is written.', Comment = 'is-IS=Les skráðar tínslur, frágang eða tilfærslur (activityType Pick, PutAway eða Movement) eftir númeri, eða eftir staðsetningu, númeri upprunaskjals og bili skráningardaga, blaðsíðuskipt með take og skip. includeLines bætir línunum við. Númeri sem er ekki til er hafnað; síur sem passa ekki við neitt skila árangri með tómum lista. Ekkert er skrifað.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>False. There are no extra notes.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := '';
        exit(false);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Validates the filters and writes one page of registered activities.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        ActivityTypeText: Text;
        ActivityNo: Text;
        LocationText: Text;
        SourceNo: Text;
        RegisteringFrom: Date;
        RegisteringTo: Date;
        ActivityType: Enum "Warehouse Activity Type";
        IncludeLines: Boolean;
        Present: Boolean;
        Skip: Integer;
        Take: Integer;
        DeniedLbl: Label 'You do not have permission to read registered warehouse activities.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa skráða vöruhúsavirkni.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
        ProblemsLbl: Label 'The request has invalid values.', Comment = 'is-IS=Beiðnin hefur ógild gildi.';
        MissingLbl: Label 'activityType is required.', Comment = 'is-IS=activityType er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send activityType Pick, PutAway or Movement.', Comment = 'is-IS=Sendu activityType Pick, PutAway eða Movement.';
        ValueLbl: Label 'Parameter %1 has the value %2, which is not one of the values listed in the help.', Comment = '%1 = parameter, %2 = value, is-IS=Færibreytan %1 hefur gildið %2 sem er ekki eitt af gildunum sem talin eru upp í hjálpinni.';
        ValueNextStepLbl: Label 'Use one of the values listed in the help.', Comment = 'is-IS=Notaðu eitt af gildunum sem talin eru upp í hjálpinni.';
        RangeLbl: Label 'The date range %1 ends before it starts.', Comment = '%1 = parameter, is-IS=Dagsetningabilið %1 endar áður en það byrjar.';
        RangeNextStepLbl: Label 'Send a from date that is on or before the to date.', Comment = 'is-IS=Sendu upphafsdagsetningu sem er sama dag eða á undan lokadagsetningu.';
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
        if Context.ReadText(RequestJson, 'activityType', 20, Argument, ActivityTypeText, Present, 'activityType') then
            if not Present then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'activityType', '', 'Pick, PutAway, Movement', MissingNextStepLbl)
            else
                case true of
                    Context.SameName(ActivityTypeText, 'Pick'):
                        ActivityType := ActivityType::Pick;
                    Context.SameName(ActivityTypeText, 'Put-away'):
                        ActivityType := ActivityType::"Put-away";
                    Context.SameName(ActivityTypeText, 'Movement'):
                        ActivityType := ActivityType::Movement;
                    else
                        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'activityType', ActivityTypeText), 'activityType', ActivityTypeText, 'Pick, PutAway, Movement', ValueNextStepLbl);
                end;
        ResolveNumber(RequestJson, Argument, ActivityNo);
        Context.ReadText(RequestJson, 'locationCode', 10, Argument, LocationText, Present, 'locationCode');
        Context.ReadText(RequestJson, 'sourceNo', 20, Argument, SourceNo, Present, 'sourceNo');
        Context.ReadDate(RequestJson, 'registeringDateFrom', Argument, RegisteringFrom, Present, 'registeringDateFrom');
        Context.ReadDate(RequestJson, 'registeringDateTo', Argument, RegisteringTo, Present, 'registeringDateTo');
        Context.ReadBoolean(RequestJson, 'includeLines', Argument, IncludeLines, Present, 'includeLines');
        if (RegisteringFrom <> 0D) and (RegisteringTo <> 0D) and (RegisteringTo < RegisteringFrom) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, 'registeringDateFrom'), 'registeringDateTo', Context.FormatDate(RegisteringTo), '', RangeNextStepLbl);
        // Every problem of the request is answered together, a bad skip or take included.
        if not Context.RespondOrReadPaging(RequestJson, Argument, ProblemsLbl, Skip, Take) then
            exit;
        RegisteredHeader.ReadIsolation := IsolationLevel::ReadCommitted;
        RegisteredHeader.SetRange(Type, ActivityType);
        if ActivityNo <> '' then begin
            RegisteredHeader.SetLoadFields(Type, "No.");
            if not RegisteredHeader.Get(ActivityType, CopyStr(UpperCase(ActivityNo), 1, MaxStrLen(RegisteredHeader."No."))) then begin
                RespondNotFound(Argument, ActivityNo);
                exit;
            end;
            RegisteredHeader.SetRange("No.", RegisteredHeader."No.");
        end;
        if LocationText <> '' then
            RegisteredHeader.SetRange("Location Code", CopyStr(UpperCase(LocationText), 1, MaxStrLen(RegisteredHeader."Location Code")));
        if (RegisteringFrom <> 0D) or (RegisteringTo <> 0D) then
            RegisteredHeader.SetRange("Registering Date", RegisteringFrom, Context.RangeEnd(RegisteringTo));
        if SourceNo <> '' then
            if not FilterBySourceNo(RegisteredHeader, ActivityType, SourceNo) then begin
                WritePage(Argument, ActivityType, RegisteredHeader, false, Skip, Take, true);
                exit;
            end;
        WritePage(Argument, ActivityType, RegisteredHeader, IncludeLines, Skip, Take, false);
    end;

    local procedure FilterBySourceNo(var RegisteredHeader: Record "Registered Whse. Activity Hdr."; ActivityType: Enum "Warehouse Activity Type"; SourceNo: Text): Boolean
    var
        RegisteredLine: Record "Registered Whse. Activity Line";
        Context: Codeunit "Whse Write Context ori";
        HeaderNos: List of [Text];
    begin
        RegisteredLine.ReadIsolation := IsolationLevel::ReadCommitted;
        RegisteredLine.SetLoadFields("Activity Type", "No.");
        RegisteredLine.SetRange("Activity Type", ActivityType);
        RegisteredLine.SetRange("Source No.", CopyStr(UpperCase(SourceNo), 1, MaxStrLen(RegisteredLine."Source No.")));
        if RegisteredLine.FindSet() then
            repeat
                if not HeaderNos.Contains(RegisteredLine."No.") then
                    HeaderNos.Add(RegisteredLine."No.");
            until RegisteredLine.Next() = 0;
        if HeaderNos.Count() = 0 then
            exit(false);
        RegisteredHeader.FilterGroup(2);
        RegisteredHeader.SetFilter("No.", Context.LiteralFilter(HeaderNos));
        RegisteredHeader.FilterGroup(0);
        exit(true);
    end;

    local procedure WritePage(var Argument: Record "Message Argument ori"; ActivityType: Enum "Warehouse Activity Type"; var RegisteredHeader: Record "Registered Whse. Activity Hdr."; IncludeLines: Boolean; Skip: Integer; Take: Integer; Empty: Boolean)
    var
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        ActivityJson: JsonObject;
        NoOfRecords: Integer;
    begin
        if not Empty then begin
            RegisteredHeader.SetLoadFields(Type, "No.", "Location Code", "Registering Date", "Whse. Activity No.", "Assigned User ID");
            NoOfRecords := RegisteredHeader.Count();
            if Skip < NoOfRecords then
                if RegisteredHeader.FindSet() then begin
                    if Skip > 0 then
                        RegisteredHeader.Next(Skip);
                    repeat
                        RecordReference.GetTable(RegisteredHeader);
                        Clear(ActivityJson);
                        ActivityJson.Add('activityType', Context.EnumValueName(RecordReference, RegisteredHeader.FieldNo(Type)));
                        ActivityJson.Add('no', RegisteredHeader."No.");
                        ActivityJson.Add('systemId', Format(RegisteredHeader.SystemId, 0, 4));
                        ActivityJson.Add('locationCode', RegisteredHeader."Location Code");
                        ActivityJson.Add('registeringDate', Context.FormatDate(RegisteredHeader."Registering Date"));
                        ActivityJson.Add('whseActivityNo', RegisteredHeader."Whse. Activity No.");
                        ActivityJson.Add('assignedUserId', RegisteredHeader."Assigned User ID");
                        if IncludeLines then
                            ActivityJson.Add('lines', LinesJson(RegisteredHeader));
                        ResultArray.Add(ActivityJson);
                        if ResultArray.Count() >= Take then
                            break;
                    until RegisteredHeader.Next() = 0;
                end;
        end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('activityType', ActivityTypeName(ActivityType));
        ResponseJson.Add('noOfRecords', NoOfRecords);
        ResponseJson.Add('skip', Skip);
        ResponseJson.Add('take', Take);
        ResponseJson.Add('result', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure LinesJson(RegisteredHeader: Record "Registered Whse. Activity Hdr.") Lines: JsonArray
    var
        RegisteredLine: Record "Registered Whse. Activity Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        LineJson: JsonObject;
    begin
        RegisteredLine.ReadIsolation := IsolationLevel::ReadCommitted;
        RegisteredLine.SetLoadFields("Activity Type", "No.", "Line No.", "Action Type", "Item No.", "Variant Code", Description, Quantity, "Unit of Measure Code", "Zone Code", "Bin Code", "Source Document", "Source No.", "Source Line No.", "Whse. Document Type", "Whse. Document No.", "Lot No.", "Serial No.");
        RegisteredLine.SetRange("Activity Type", RegisteredHeader.Type);
        RegisteredLine.SetRange("No.", RegisteredHeader."No.");
        if RegisteredLine.FindSet() then
            repeat
                RecordReference.GetTable(RegisteredLine);
                Clear(LineJson);
                LineJson.Add('lineNo', RegisteredLine."Line No.");
                LineJson.Add('actionType', Context.EnumValueName(RecordReference, RegisteredLine.FieldNo("Action Type")));
                LineJson.Add('itemNo', RegisteredLine."Item No.");
                LineJson.Add('variantCode', RegisteredLine."Variant Code");
                LineJson.Add('description', RegisteredLine.Description);
                LineJson.Add('quantity', RegisteredLine.Quantity);
                LineJson.Add('unitOfMeasureCode', RegisteredLine."Unit of Measure Code");
                LineJson.Add('zoneCode', RegisteredLine."Zone Code");
                LineJson.Add('binCode', RegisteredLine."Bin Code");
                LineJson.Add('sourceDocument', Context.EnumValueName(RecordReference, RegisteredLine.FieldNo("Source Document")));
                LineJson.Add('sourceNo', RegisteredLine."Source No.");
                LineJson.Add('sourceLineNo', RegisteredLine."Source Line No.");
                LineJson.Add('whseDocumentType', Context.EnumValueName(RecordReference, RegisteredLine.FieldNo("Whse. Document Type")));
                LineJson.Add('whseDocumentNo', RegisteredLine."Whse. Document No.");
                LineJson.Add('lotNo', RegisteredLine."Lot No.");
                LineJson.Add('serialNo', RegisteredLine."Serial No.");
                Lines.Add(LineJson);
            until RegisteredLine.Next() = 0;
    end;

    local procedure ActivityTypeName(ActivityType: Enum "Warehouse Activity Type"): Text
    begin
        exit(ActivityType.Names().Get(ActivityType.Ordinals().IndexOf(ActivityType.AsInteger())));
    end;

    local procedure RespondNotFound(var Argument: Record "Message Argument ori"; ActivityNo: Text)
    var
        NotFoundLbl: Label 'Registered warehouse activity %1 was not found.', Comment = '%1 = activity no., is-IS=Skráð vöruhúsavirkni %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Search with filters instead of a no.', Comment = 'is-IS=Leitaðu með síum í stað númers.';
    begin
        Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ActivityNo), 'no', ActivityNo, '', NotFoundNextStepLbl);
    end;

    local procedure ResolveNumber(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var ActivityNo: Text)
    var
        Context: Codeunit "Whse Write Context ori";
        SubjectText: Text;
        Present: Boolean;
        ConflictLbl: Label 'subject and no name different activities.', Comment = 'is-IS=subject og no nefna mismunandi virkni.';
        ConflictNextStepLbl: Label 'Send one number: subject or no.', Comment = 'is-IS=Sendu eitt númer: subject eða no.';
    begin
        ActivityNo := '';
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'no', 20, Argument, ActivityNo, Present, 'no') then
            exit;
        if Present and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(ActivityNo)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'no', ActivityNo, SubjectText, ConflictNextStepLbl);
            exit;
        end;
        if not Present then
            ActivityNo := SubjectText;
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['activityType', 'no', 'locationCode', 'sourceNo', 'registeringDateFrom', 'registeringDateTo', 'includeLines', 'skip', 'take']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;
}
