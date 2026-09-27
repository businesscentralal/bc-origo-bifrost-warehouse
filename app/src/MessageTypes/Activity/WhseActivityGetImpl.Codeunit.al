namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Activity.Get as a filtered, paged read of open warehouse activities.
/// </summary>
codeunit 10036940 "Whse Activity Get Impl ori" implements "Msg Interface ori"
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

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Returns the request and response help for the message type.</summary>
    /// <param name="Argument">The message argument receiving the help.</param>
    procedure GetMessageHelpAsMarkdownDocument(var Argument: Record "Message Argument ori")
    var
        HelpCodeunit: Codeunit "Whse Activity Get Help ori";
    begin
        Argument.SetResponseMarkdown(HelpCodeunit.GetHelpText());
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
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();

        RequestJson := Argument.GetRequestJson();
        Argument.EvaluateSkipTake(RequestJson, Skip, Take);

        if TryGetRequestText(RequestJson, 'activityType', ActivityTypeText) then begin
            ActivityTypeSpecified := true;
            if not TryParseActivityType(ActivityTypeText, ActivityType) then begin
                Argument.RespondWithError(StrSubstNo('Unknown warehouse activity type: %1.', ActivityTypeText));
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
                        Argument.RespondWithError(StrSubstNo('Invalid systemId: %1.', SystemIdText));
                        exit;
                    end;
                    SingleLookup := true;
                end;

        if (ActivityNo = '') and (SystemIdText = '') and (Argument.Subject <> '') then begin
            if Argument.SubjectIsGuid() then begin
                SystemIdText := Argument.Subject;
                if not Evaluate(ActivitySystemId, SystemIdText, 9) then begin
                    Argument.RespondWithError(StrSubstNo('Invalid activity subject: %1.', SystemIdText));
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

        if ActivityHeader.FindSet() then begin
            repeat
                if not HasDocumentFilter or ActivityHeaderKeys.Contains(GetActivityKey(ActivityHeader.Type, ActivityHeader."No.")) then
                    NoOfRecords += 1;
            until ActivityHeader.Next() = 0;
        end;

        if SingleLookup and (NoOfRecords = 0) then begin
            if ActivityNo <> '' then
                Argument.RespondWithError(StrSubstNo('Warehouse Activity %1 does not exist.', ActivityNo))
            else
                Argument.RespondWithError(StrSubstNo('Warehouse Activity %1 does not exist.', SystemIdText));
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
        ActivityLine.SetAutoCalcFields("Qty. Outstanding");
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