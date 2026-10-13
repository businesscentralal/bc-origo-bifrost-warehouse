namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Activity.Get as a filtered, paged read of open warehouse activities.
/// </summary>
codeunit 10078390 "Whse Activity Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read Warehouse Activity Header.</summary>
    /// <returns>True when the caller has read permission on Warehouse Activity Header.</returns>
    procedure IsEnabled(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(GetFilterTableNo());
        exit(RecRef.ReadPermission());
    end;

    /// <summary>Returns the table used to evaluate caller read permission.</summary>
    /// <returns>The Warehouse Activity Header table ID.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Header");
    end;

    /// <summary>Returns a short description of Warehouse.Activity.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    begin
        exit('Reads open warehouse activities with optional header, document and line filters.');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'warehouse activity, open pick, open put-away, warehouse lines, activity header, activity lines', Comment = 'is-IS=vöruhúsavirkni, opin tínsla, opinn frágangur, vöruhúslínur, haus virkni, línur virkni';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Reads open warehouse picks and put-aways; use Warehouse.BinContent.Get for bin stock.', Comment = 'is-IS=Lesaðgangur. Les opnar tínslur og fráganga í vöruhúsi; notaðu Warehouse.BinContent.Get fyrir birgðir í hólfum.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('guid');
        Forms.Add('activity no.');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional Warehouse Activity Header SystemId or activity number; omit it to read a collection.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Target := Parts.ActivityTarget('Warehouse Activity', 'activityNo');
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddPagingParameters(Parameters);
        Parameters.Add(ContractMgt.Parameter('activityType', 'string', false, 'Warehouse activity type, for example Pick or Put-away.'));
        Parameters.Add(ContractMgt.Parameter('no', 'string', false, 'Warehouse activity number.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'Warehouse Activity Header SystemId. recordSystemId and id are accepted too.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Filter by location code.'));
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'Filter by assigned user.'));
        Parameters.Add(ContractMgt.Parameter('whseDocumentNo', 'string', false, 'Filter activities by source warehouse document number.'));
        Parameters.Add(ContractMgt.Parameter('includeLines', 'boolean', false, 'Include the activity lines in each result.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        ActivityFields: JsonArray;
        LineFields: JsonArray;
        Activity: JsonObject;
        Lines: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('noOfRecords', 'integer', 'Total matching open activities before paging.'));
        Fields.Add(ContractMgt.ResponseField('skip', 'integer', 'Number of activities skipped.'));
        Fields.Add(ContractMgt.ResponseField('take', 'integer', 'Maximum number of activities requested.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Activity line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin code.'));
        LineFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone code.'));
        LineFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure code.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle.'));
        LineFields.Add(ContractMgt.ResponseField('qtyHandled', 'number', 'Quantity already handled.'));
        LineFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Quantity outstanding.'));
        LineFields.Add(ContractMgt.ResponseField('actionType', 'string', 'Warehouse action type.'));
        LineFields.Add(ContractMgt.ResponseField('whseDocumentType', 'string', 'Source warehouse document type.'));
        LineFields.Add(ContractMgt.ResponseField('whseDocumentNo', 'string', 'Source warehouse document number.'));
        LineFields.Add(ContractMgt.ResponseField('whseDocumentLineNo', 'integer', 'Source warehouse document line number.'));
        ActivityFields.Add(ContractMgt.ResponseField('no', 'string', 'Warehouse activity number.'));
        ActivityFields.Add(ContractMgt.ResponseField('systemId', 'string', 'Warehouse Activity Header SystemId.'));
        ActivityFields.Add(ContractMgt.ResponseField('activityType', 'string', 'Warehouse activity type.'));
        ActivityFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        ActivityFields.Add(ContractMgt.ResponseField('assignedUserId', 'string', 'Assigned user ID.'));
        ActivityFields.Add(ContractMgt.ResponseField('sortingMethod', 'string', 'Warehouse activity sorting method.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Included when includeLines is true.');
        Lines.Add('children', LineFields);
        ActivityFields.Add(Lines);
        Activity.Add('name', 'result');
        Activity.Add('type', 'array');
        Activity.Add('description', 'The paged open Warehouse Activity Header rows.');
        Activity.Add('children', ActivityFields);
        Fields.Add(Activity);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddLookupErrors(Errors, 'Warehouse Activity Header');
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, 'activityType is not a valid warehouse activity type.', 'Use a value from the Warehouse Activity Type enum.'));
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads open Warehouse Activity Header and Line records and changes nothing.', 'BIFROST Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read bin stock rather than open warehouse activities.'));
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    begin
        exit(false);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only access to open Warehouse Activity Header records, optionally including their lines and source-document filter.';
        exit(true);
    end;

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

    /// <summary>Reads matching open warehouse activities and returns a paged JSON result.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        ResultJson: JsonObject;
        ActivityHeaderKeys: List of [Text];
        ActivityType: Enum "Warehouse Activity Type";
        ActivityNo: Code[20];
        ActivityTypeText: Text;
        RequestValue: Text;
        SystemIdText: Text;
        WhseDocumentNo: Code[20];
        LocationCode: Code[10];
        AssignedUserId: Code[50];
        ActivitySystemId: Guid;
        Skip: Integer;
        Take: Integer;
        NoOfRecords: Integer;
        MatchedRecords: Integer;
        IncludeLines: Boolean;
        ActivityTypeSpecified: Boolean;
        HasDocumentFilter: Boolean;
        SingleLookup: Boolean;
        NotFoundErr: Label '%1 "%2" was not found (from %3).', Comment = '%1 = table caption, %2 = value received, %3 = JSON key, is-IS=%1 "%2" fannst ekki (úr %3).';
        NotFoundNextStepTxt: Label 'Check the number with Data.Records.Get on table %1.', Comment = '%1 = table caption, is-IS=Athugaðu númerið með Data.Records.Get á töflunni %1.';
        InvalidFormatErr: Label '"%1" is not a valid %2 (from %3).', Comment = '%1 = value received, %2 = expected format, %3 = JSON key or subject, is-IS="%1" er ekki gilt %2 (úr %3).';
        InvalidActivityTypeErr: Label '"%1" is not a valid warehouse activity type (from activityType).', Comment = '%1 = received value, is-IS="%1" er ekki gild tegund vöruhúsavirkni (úr activityType).';
        GuidTok: Label 'GUID', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();

        RequestJson := Argument.GetRequestJson();
        Argument.EvaluateSkipTake(RequestJson, Skip, Take);

        if TryGetRequestText(RequestJson, 'activityType', ActivityTypeText) then begin
            ActivityTypeSpecified := true;
            if not TryParseActivityType(ActivityTypeText, ActivityType) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidActivityTypeErr, ActivityTypeText), 'activityType', ActivityTypeText, '', '');
                exit;
            end;
        end;

        if TryGetRequestText(RequestJson, 'no', RequestValue) then
            if RequestValue <> '' then begin
                ActivityNo := CopyStr(RequestValue, 1, MaxStrLen(ActivityNo));
                SingleLookup := true;
            end;

        if ActivityNo = '' then
            if TryGetRequestText(RequestJson, 'systemId', SystemIdText) then
                if SystemIdText <> '' then begin
                    if not Evaluate(ActivitySystemId, SystemIdText, 9) then begin
                        Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(InvalidFormatErr, SystemIdText, GuidTok, 'systemId'), 'systemId', SystemIdText, GuidTok, '');
                        exit;
                    end;
                    SingleLookup := true;
                end;

        if (ActivityNo = '') and (SystemIdText = '') and (Argument.Subject <> '') then begin
            if Argument.SubjectIsGuid() then begin
                SystemIdText := Argument.Subject;
                if not Evaluate(ActivitySystemId, SystemIdText, 9) then begin
                    Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(InvalidFormatErr, SystemIdText, GuidTok, 'subject'), 'subject', SystemIdText, GuidTok, '');
                    exit;
                end;
            end else
                ActivityNo := CopyStr(Argument.Subject, 1, MaxStrLen(ActivityNo));
            SingleLookup := true;
        end;

        if ActivityNo <> '' then
            ActivityHeader.SetRange("No.", ActivityNo);
        if SystemIdText <> '' then
            ActivityHeader.SetRange(SystemId, ActivitySystemId);
        if ActivityTypeSpecified then
            ActivityHeader.SetRange(Type, ActivityType);

        if TryGetRequestText(RequestJson, 'locationCode', RequestValue) then begin
            LocationCode := CopyStr(RequestValue, 1, MaxStrLen(LocationCode));
            ActivityHeader.SetRange("Location Code", LocationCode);
        end;
        if TryGetRequestText(RequestJson, 'assignedUserId', RequestValue) then begin
            AssignedUserId := CopyStr(RequestValue, 1, MaxStrLen(AssignedUserId));
            ActivityHeader.SetRange("Assigned User ID", AssignedUserId);
        end;
        if TryGetRequestText(RequestJson, 'whseDocumentNo', RequestValue) then begin
            WhseDocumentNo := CopyStr(RequestValue, 1, MaxStrLen(WhseDocumentNo));
            HasDocumentFilter := true;
        end;
        TryGetRequestBoolean(RequestJson, 'includeLines', IncludeLines);

        ActivityHeader.ReadIsolation := IsolationLevel::ReadCommitted;
        ActivityHeader.SetLoadFields("No.", SystemId, Type, "Location Code", "Assigned User ID", "Sorting Method");
        ActivityHeader.SetPermissionFilter();

        if HasDocumentFilter then begin
            ActivityLine.ReadIsolation := IsolationLevel::ReadCommitted;
            ActivityLine.SetLoadFields("Activity Type", "No.", "Whse. Document No.");
            ActivityLine.SetRange("Whse. Document No.", WhseDocumentNo);
            ActivityLine.SetPermissionFilter();
            if ActivityLine.FindSet() then
                repeat
                    if not ActivityHeaderKeys.Contains(GetActivityKey(ActivityLine."Activity Type", ActivityLine."No.")) then
                        ActivityHeaderKeys.Add(GetActivityKey(ActivityLine."Activity Type", ActivityLine."No."));
                until ActivityLine.Next() = 0;
        end;

        if ActivityHeader.FindSet() then
            repeat
                if not HasDocumentFilter or ActivityHeaderKeys.Contains(GetActivityKey(ActivityHeader.Type, ActivityHeader."No.")) then
                    NoOfRecords += 1;
            until ActivityHeader.Next() = 0;

        if SingleLookup and (NoOfRecords = 0) then begin
            if ActivityNo <> '' then
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundErr, ActivityHeader.TableCaption(), ActivityNo, 'no'), 'no', ActivityNo, '', StrSubstNo(NotFoundNextStepTxt, ActivityHeader.TableCaption()))
            else
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundErr, ActivityHeader.TableCaption(), SystemIdText, 'systemId'), 'systemId', SystemIdText, '', StrSubstNo(NotFoundNextStepTxt, ActivityHeader.TableCaption()));
            exit;
        end;

        if (Skip < NoOfRecords) and ActivityHeader.FindSet() then
            repeat
                if not HasDocumentFilter or ActivityHeaderKeys.Contains(GetActivityKey(ActivityHeader.Type, ActivityHeader."No.")) then begin
                    if MatchedRecords >= Skip then begin
                        Clear(ResultJson);
                        ResultJson.Add('no', ActivityHeader."No.");
                        ResultJson.Add('systemId', Format(ActivityHeader.SystemId, 0, 4));
                        ResultJson.Add('activityType', GetActivityTypeName(ActivityHeader.Type));
                        ResultJson.Add('locationCode', ActivityHeader."Location Code");
                        ResultJson.Add('assignedUserId', ActivityHeader."Assigned User ID");
                        ResultJson.Add('sortingMethod', GetSortingMethodName(ActivityHeader."Sorting Method"));
                        if IncludeLines then
                            AddActivityLines(ResultJson, ActivityHeader);
                        ResultArray.Add(ResultJson);
                        if ResultArray.Count() >= Take then
                            break;
                    end;
                    MatchedRecords += 1;
                end;
            until ActivityHeader.Next() = 0;

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('noOfRecords', NoOfRecords);
        ResponseJson.Add('skip', Skip);
        ResponseJson.Add('take', Take);
        ResponseJson.Add('result', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure AddActivityLines(var ActivityJson: JsonObject; ActivityHeader: Record "Warehouse Activity Header")
    var
        ActivityLine: Record "Warehouse Activity Line";
        LineArray: JsonArray;
        LineJson: JsonObject;
    begin
        ActivityLine.ReadIsolation := IsolationLevel::ReadCommitted;
        ActivityLine.SetLoadFields(
            "Line No.", "Item No.", "Bin Code", "Zone Code", "Unit of Measure Code",
            "Qty. to Handle", "Qty. Handled", "Qty. Outstanding", "Action Type",
            "Whse. Document Type", "Whse. Document No.", "Whse. Document Line No.");
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        ActivityLine.SetPermissionFilter();

        if ActivityLine.FindSet() then
            repeat
                Clear(LineJson);
                LineJson.Add('lineNo', ActivityLine."Line No.");
                LineJson.Add('itemNo', ActivityLine."Item No.");
                LineJson.Add('binCode', ActivityLine."Bin Code");
                LineJson.Add('zoneCode', ActivityLine."Zone Code");
                LineJson.Add('unitOfMeasureCode', ActivityLine."Unit of Measure Code");
                LineJson.Add('qtyToHandle', ActivityLine."Qty. to Handle");
                LineJson.Add('qtyHandled', ActivityLine."Qty. Handled");
                LineJson.Add('qtyOutstanding', ActivityLine."Qty. Outstanding");
                LineJson.Add('actionType', GetActionTypeName(ActivityLine."Action Type"));
                LineJson.Add('whseDocumentType', GetDocumentTypeName(ActivityLine."Whse. Document Type"));
                LineJson.Add('whseDocumentNo', ActivityLine."Whse. Document No.");
                LineJson.Add('whseDocumentLineNo', ActivityLine."Whse. Document Line No.");
                LineArray.Add(LineJson);
            until ActivityLine.Next() = 0;

        ActivityJson.Add('lines', LineArray);
    end;

    local procedure TryParseActivityType(Value: Text; var ActivityType: Enum "Warehouse Activity Type"): Boolean
    var
        EnumNames: List of [Text];
        EnumOrdinals: List of [Integer];
        EnumName: Text;
        EnumOrdinal: Integer;
        Index: Integer;
    begin
        EnumNames := Enum::"Warehouse Activity Type".Names();
        EnumOrdinals := Enum::"Warehouse Activity Type".Ordinals();
        for Index := 1 to EnumNames.Count() do begin
            EnumNames.Get(Index, EnumName);
            if EnumName = Value then begin
                EnumOrdinals.Get(Index, EnumOrdinal);
                ActivityType := Enum::"Warehouse Activity Type".FromInteger(EnumOrdinal);
                exit(true);
            end;
        end;
        exit(false);
    end;

    local procedure GetActivityKey(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]): Text
    begin
        exit(Format(ActivityType.AsInteger(), 0, 9) + '|' + ActivityNo);
    end;

    local procedure GetActivityTypeName(ActivityType: Enum "Warehouse Activity Type"): Text
    begin
        exit(GetEnumName(
            Enum::"Warehouse Activity Type".Names(),
            Enum::"Warehouse Activity Type".Ordinals(),
            ActivityType.AsInteger()));
    end;

    local procedure GetSortingMethodName(SortingMethod: Enum "Whse. Activity Sorting Method"): Text
    begin
        exit(GetEnumName(
            Enum::"Whse. Activity Sorting Method".Names(),
            Enum::"Whse. Activity Sorting Method".Ordinals(),
            SortingMethod.AsInteger()));
    end;

    local procedure GetActionTypeName(ActionType: Enum "Warehouse Action Type"): Text
    begin
        exit(GetEnumName(
            Enum::"Warehouse Action Type".Names(),
            Enum::"Warehouse Action Type".Ordinals(),
            ActionType.AsInteger()));
    end;

    local procedure GetDocumentTypeName(DocumentType: Enum "Warehouse Activity Document Type"): Text
    begin
        exit(GetEnumName(
            Enum::"Warehouse Activity Document Type".Names(),
            Enum::"Warehouse Activity Document Type".Ordinals(),
            DocumentType.AsInteger()));
    end;

    local procedure GetEnumName(EnumNames: List of [Text]; EnumOrdinals: List of [Integer]; EnumOrdinal: Integer): Text
    var
        EnumName: Text;
        CurrentOrdinal: Integer;
        Index: Integer;
    begin
        for Index := 1 to EnumOrdinals.Count() do begin
            EnumOrdinals.Get(Index, CurrentOrdinal);
            if CurrentOrdinal = EnumOrdinal then begin
                EnumNames.Get(Index, EnumName);
                if EnumName = '' then
                    exit('None');
                exit(EnumName);
            end;
        end;
        exit('');
    end;

    local procedure TryGetRequestText(RequestJson: JsonObject; PropertyName: Text; var Value: Text): Boolean
    var
        Token: JsonToken;
    begin
        Clear(Value);
        if not RequestJson.Get(PropertyName, Token) then
            exit(false);
        if not Token.IsValue() or Token.AsValue().IsNull() then
            exit(false);
        Value := Token.AsValue().AsText();
        exit(true);
    end;

    local procedure TryGetRequestBoolean(RequestJson: JsonObject; PropertyName: Text; var Value: Boolean): Boolean
    var
        Token: JsonToken;
        BooleanText: Text;
    begin
        Clear(Value);
        if not RequestJson.Get(PropertyName, Token) then
            exit(false);
        if not Token.IsValue() or Token.AsValue().IsNull() then
            exit(false);
        BooleanText := LowerCase(Token.AsValue().AsText());
        if (BooleanText <> 'true') and (BooleanText <> 'false') then
            exit(false);
        Value := BooleanText = 'true';
        exit(true);
    end;
}