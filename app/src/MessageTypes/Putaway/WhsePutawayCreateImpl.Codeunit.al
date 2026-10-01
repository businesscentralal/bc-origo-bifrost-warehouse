namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Putaway.Create message type.
/// Wraps BC's "Whse.-Source - Create Document" report (7305) to generate a Warehouse Activity
/// Header (Type = Put-away) from a Posted Whse. Receipt. After creation the optional
/// `assignedUserId` and `sortingMethod` are applied to the activity header (subject to
/// write-restrictions on those fields).
///
/// The actual report invocation is delegated to "Whse Putaway Create Proc. ori" via Codeunit.Run
/// so report-time errors are caught and returned as Error responses without rolling back the
/// outer message-task transaction.
/// </summary>

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.History;

using Origo.Bifrost;

codeunit 10078415 "Whse Putaway Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    procedure IsEnabled(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(GetFilterTableNo());
        exit(RecRef.WritePermission());
    end;
    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Posted Whse. Receipt Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Creates a Warehouse Put-away from a Posted Whse. Receipt (BC report 7305 "Whse.-Source - Create Document").');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create put-away, put away, putaway, shelve the goods, store received goods', Comment = 'is-IS=stofna frágang, ganga frá vörum, frágangur, setja vörur í hillur, geyma mótteknar vörur';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Creates or returns a Warehouse Put-away from a posted receipt; use Warehouse.Putaway.Register after the goods are put away.', Comment = 'is-IS=Stofnar eða skilar frágangi úr bókaðri móttöku; notaðu Warehouse.Putaway.Register eftir að gengið hefur verið frá vörunum.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('guid');
        Forms.Add('document no.');
        Envelope := Parts.RecordEnvelope(Forms, 'The Posted Warehouse Receipt from which the put-away is created: its SystemId or No.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Target := Parts.RecordTarget('Posted Whse. Receipt Header', 'systemId, recordSystemId, id, postedWhseReceiptNo, receiptNo, no');
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddActivityParameters(Parameters, true);
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('postedWhseReceiptNo', 'string', 'Source Posted Warehouse Receipt number.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseReceiptSystemId', 'string', 'Source Posted Warehouse Receipt SystemId.'));
        Fields.Add(ContractMgt.ResponseField('putawayNo', 'string', 'Created or returned Warehouse Put-away number.'));
        Fields.Add(ContractMgt.ResponseField('putawaySystemId', 'string', 'Warehouse Put-away SystemId.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Warehouse location code.'));
        Fields.Add(ContractMgt.ResponseField('assignedUserId', 'string', 'Assigned user.'));
        Fields.Add(ContractMgt.ResponseField('sortingMethod', 'string', 'Sorting method.'));
        Fields.Add(ContractMgt.ResponseField('alreadyExisted', 'boolean', 'True when BC had already created the open put-away.'));
        Fields.Add(ContractMgt.ResponseField('totalPutawayLines', 'integer', 'Number of put-away lines.'));
        Fields.Add(ContractMgt.ResponseField('totalQtyToHandle', 'number', 'Total quantity to handle.'));
        Fields.Add(ContractMgt.ResponseField('message', 'string', 'Human-readable result.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddLookupErrors(Errors, 'Posted Whse. Receipt Header');
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, 'A sortingMethod or report option is not valid.', 'Use a valid sorting method and leave unsupported report options false.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'No Warehouse Put-away exists or could be created for the posted receipt.', 'Ensure the receipt has outstanding quantities and the location requires put-away.'));
        Parts.AddBusinessCentralError(Errors, 'missing warehouse setup, no quantities to put away or report validation failure');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Creates or returns Warehouse Activity Header and Line records of type Put-away and applies optional activity fields.', 'BIFROST Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'Use it first when the Warehouse Receipt has not been posted.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Register', 'Use it after the goods are put away to register the activity.'));
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
        Overview := 'Creates a Warehouse Put-away from a Posted Warehouse Receipt, or returns an already-created open put-away.';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Clear(Notes);
        exit(false);
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure GetMessageHelpAsMarkdownDocument(var Argument: Record "Message Argument ori")
    begin
        Argument.SetResponseMarkdown('');
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        Dispatcher: Codeunit "Dispatcher ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        SortingMethodText: Text;
        AssignedUserIdValue: Code[50];
        SortingMethodValue: Enum "Whse. Activity Sorting Method";
        SetBreakbulkFilter: Boolean;
        DoNotFillQtyToHandle: Boolean;
        HasAssignedUserId: Boolean;
        HasSortingMethod: Boolean;
        PutawayWasCreated: Boolean;
        AlreadyExisted: Boolean;
        ReportErrorText: Text;
        FieldWriteRestrictedErr: Label 'Field %1 is restricted for write on table %2.', Comment = '%1 = field caption, %2 = table caption', Locked = true;
        UnsupportedOptionErr: Label '%1 = true is not supported by this API version. Only the BC defaults (false) are honoured.', Comment = '%1 = option name', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        RequestJson := Argument.GetRequestJson();

        if not FindPostedWhseReceiptHeader(Argument, PostedWhseReceiptHeader) then
            exit;

        // Optional assignedUserId — written to Warehouse Activity Header after creation; honour write restriction.
        AssignedUserIdValue := ReadCode50(RequestJson, 'assignedUserId');
        HasAssignedUserId := AssignedUserIdValue <> '';
        if HasAssignedUserId then
            if Dispatcher.IsFieldWriteRestricted(Database::"Warehouse Activity Header", WarehouseActivityHeader.FieldNo("Assigned User ID")) then begin
                Argument.RespondWithError(StrSubstNo(FieldWriteRestrictedErr, WarehouseActivityHeader.FieldCaption("Assigned User ID"), WarehouseActivityHeader.TableCaption()));
                exit;
            end;

        // Optional sortingMethod — written to Warehouse Activity Header after creation; honour write restriction.
        SortingMethodText := ReadString(RequestJson, 'sortingMethod');
        if SortingMethodText <> '' then begin
            if not TryParseSortingMethod(SortingMethodText, SortingMethodValue) then begin
                Argument.RespondWithError(BuildInvalidSortingMethodErr(SortingMethodText));
                exit;
            end;
            if Dispatcher.IsFieldWriteRestricted(Database::"Warehouse Activity Header", WarehouseActivityHeader.FieldNo("Sorting Method")) then begin
                Argument.RespondWithError(StrSubstNo(FieldWriteRestrictedErr, WarehouseActivityHeader.FieldCaption("Sorting Method"), WarehouseActivityHeader.TableCaption()));
                exit;
            end;
            HasSortingMethod := true;
        end;

        // setBreakbulkFilter / doNotFillQtyToHandle are request-page-only on BC report 7305.
        // We accept the defaults silently; non-default values are rejected to avoid silent loss.
        SetBreakbulkFilter := ReadBoolean(RequestJson, 'setBreakbulkFilter');
        if SetBreakbulkFilter then begin
            Argument.RespondWithError(StrSubstNo(UnsupportedOptionErr, 'setBreakbulkFilter'));
            exit;
        end;
        DoNotFillQtyToHandle := ReadBoolean(RequestJson, 'doNotFillQtyToHandle');
        if DoNotFillQtyToHandle then begin
            Argument.RespondWithError(StrSubstNo(UnsupportedOptionErr, 'doNotFillQtyToHandle'));
            exit;
        end;

        // Delegate the report invocation to an isolated codeunit so report-time errors are
        // caught here without aborting the outer message-task transaction.
        PutawayWasCreated := Codeunit.Run(Codeunit::"Whse Putaway Create Proc. ori", PostedWhseReceiptHeader);
        ReportErrorText := GetLastErrorText();

        // Locate the put-away for this Posted Whse. Receipt. A put-away may already exist even
        // when the report failed: on a Require Put-away location that is NOT a "Use Put-away
        // Worksheet" location, BC auto-creates the put-away while posting the receipt (base app
        // codeunit 5760 "Whse.-Post Receipt" — ShouldCreatePutAway = Require Put-away AND NOT
        // Use Put-away Worksheet). Report 7305 then raises "There is nothing to handle." Rather
        // than surface that cryptic error, treat an already-existing open put-away as an
        // idempotent success and return it (flagged via "alreadyExisted").
        if not FindCreatedPutaway(PostedWhseReceiptHeader."No.", WarehouseActivityHeader) then begin
            if PutawayWasCreated then
                Argument.RespondWithError(StrSubstNo(NoPutawayCreatedErr(), PostedWhseReceiptHeader."No."))
            else
                Argument.RespondWithError(ReportErrorText);
            exit;
        end;
        AlreadyExisted := not PutawayWasCreated;

        if HasAssignedUserId then begin
            WarehouseActivityHeader.Validate("Assigned User ID", AssignedUserIdValue);
            WarehouseActivityHeader.Modify(true);
        end;
        if HasSortingMethod then begin
            WarehouseActivityHeader.Validate("Sorting Method", SortingMethodValue);
            WarehouseActivityHeader.Modify(true);
        end;

        BuildResponse(PostedWhseReceiptHeader, WarehouseActivityHeader, AlreadyExisted, ResponseJson);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindPostedWhseReceiptHeader(var Argument: Record "Message Argument ori"; var PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
    begin
        // Every identifier sent is tried; the shared lookup answers missing, not found and conflicts.
        if not WhseRecordLookup.FindRecord(Argument, Database::"Posted Whse. Receipt Header", 'guid|no', 'systemId=guid,recordSystemId=guid,id=guid,postedWhseReceiptNo=no,receiptNo=no,no=no', FoundSystemId) then
            exit(false);
        exit(PostedWhseReceiptHeader.GetBySystemId(FoundSystemId));
    end;

    local procedure FindCreatedPutaway(PostedWhseReceiptNo: Code[20]; var WarehouseActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        WarehouseActivityLine: Record "Warehouse Activity Line";
    begin
        // Put-away activity lines reference the source Posted Whse. Receipt via
        // "Whse. Document Type" = Receipt and "Whse. Document No.".
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("Whse. Document Type", WarehouseActivityLine."Whse. Document Type"::Receipt);
        WarehouseActivityLine.SetRange("Whse. Document No.", PostedWhseReceiptNo);
        WarehouseActivityLine.SetCurrentKey("No.");
        if not WarehouseActivityLine.FindLast() then
            exit(false);
        WarehouseActivityHeader.SetRange(Type, WarehouseActivityHeader.Type::"Put-away");
        WarehouseActivityHeader.SetRange("No.", WarehouseActivityLine."No.");
        exit(WarehouseActivityHeader.FindFirst());
    end;

    local procedure BuildResponse(PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header"; WarehouseActivityHeader: Record "Warehouse Activity Header"; AlreadyExisted: Boolean; var ResponseJson: JsonObject)
    var
        WarehouseActivityLine: Record "Warehouse Activity Line";
        TotalQtyToHandle: Decimal;
        TotalLines: Integer;
        CreatedMsg: Label 'Warehouse Put-away %1 created from Posted Receipt %2 with %3 lines.', Comment = '%1 = put-away no., %2 = posted receipt no., %3 = line count', Locked = true;
        ExistingMsg: Label 'Warehouse Put-away %1 already existed for Posted Receipt %2 (auto-created at receipt posting) and was returned with %3 lines.', Comment = '%1 = put-away no., %2 = posted receipt no., %3 = line count', Locked = true;
    begin
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        TotalLines := WarehouseActivityLine.Count();
        WarehouseActivityLine.CalcSums("Qty. to Handle");
        TotalQtyToHandle := WarehouseActivityLine."Qty. to Handle";

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('postedWhseReceiptNo', PostedWhseReceiptHeader."No.");
        ResponseJson.Add('postedWhseReceiptSystemId', Format(PostedWhseReceiptHeader.SystemId, 0, 4));
        ResponseJson.Add('putawayNo', WarehouseActivityHeader."No.");
        ResponseJson.Add('putawaySystemId', Format(WarehouseActivityHeader.SystemId, 0, 4));
        ResponseJson.Add('locationCode', WarehouseActivityHeader."Location Code");
        ResponseJson.Add('assignedUserId', WarehouseActivityHeader."Assigned User ID");
        ResponseJson.Add('sortingMethod', SortingMethodName(WarehouseActivityHeader."Sorting Method"));
        ResponseJson.Add('alreadyExisted', AlreadyExisted);
        ResponseJson.Add('totalPutawayLines', TotalLines);
        ResponseJson.Add('totalQtyToHandle', TotalQtyToHandle);
        if AlreadyExisted then
            ResponseJson.Add('message', StrSubstNo(ExistingMsg, WarehouseActivityHeader."No.", PostedWhseReceiptHeader."No.", TotalLines))
        else
            ResponseJson.Add('message', StrSubstNo(CreatedMsg, WarehouseActivityHeader."No.", PostedWhseReceiptHeader."No.", TotalLines));
    end;

    local procedure SortingMethodName(SortingMethod: Enum "Whse. Activity Sorting Method") Name: Text
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        Index: Integer;
        DefaultNameTok: Label 'None', Locked = true;
    begin
        Names := Enum::"Whse. Activity Sorting Method".Names();
        Ordinals := Enum::"Whse. Activity Sorting Method".Ordinals();
        Index := Ordinals.IndexOf(SortingMethod.AsInteger());
        if Index = 0 then
            exit(DefaultNameTok);
        Name := Names.Get(Index);
        if DelChr(Name, '=', ' ') = '' then
            exit(DefaultNameTok);
    end;

    local procedure TryParseSortingMethod(SortingMethodText: Text; var SortingMethodValue: Enum "Whse. Activity Sorting Method"): Boolean
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        Index: Integer;
    begin
        Names := Enum::"Whse. Activity Sorting Method".Names();
        Ordinals := Enum::"Whse. Activity Sorting Method".Ordinals();
        Index := IndexOfCaseInsensitive(Names, SortingMethodText);
        if Index = 0 then
            exit(false);
        SortingMethodValue := Enum::"Whse. Activity Sorting Method".FromInteger(Ordinals.Get(Index));
        exit(true);
    end;

    local procedure IndexOfCaseInsensitive(Names: List of [Text]; Value: Text): Integer
    var
        Idx: Integer;
        Comparand: Text;
    begin
        Comparand := UpperCase(Value);
        for Idx := 1 to Names.Count() do
            if UpperCase(Names.Get(Idx)) = Comparand then
                exit(Idx);
        exit(0);
    end;

    local procedure BuildInvalidSortingMethodErr(SortingMethodText: Text) ErrMessage: Text
    var
        Names: List of [Text];
        Idx: Integer;
        Builder: TextBuilder;
        InvalidErr: Label 'sortingMethod ''%1'' is not valid. Expected one of: %2.', Comment = '%1 = supplied value, %2 = comma list of valid values', Locked = true;
    begin
        Names := Enum::"Whse. Activity Sorting Method".Names();
        for Idx := 1 to Names.Count() do begin
            if Idx > 1 then
                Builder.Append(', ');
            Builder.Append(Names.Get(Idx));
        end;
        ErrMessage := StrSubstNo(InvalidErr, SortingMethodText, Builder.ToText());
    end;

    local procedure NoPutawayCreatedErr() Result: Text
    var
        Err: Label 'No Warehouse Put-away was created for Posted Whse. Receipt %1. There may be nothing to put away, the location may not require put-away, or all lines may already be completely put away.', Comment = '%1 = posted receipt no.', Locked = true;
    begin
        Result := Err;
    end;

    local procedure ReadString(JObject: JsonObject; PropertyName: Text): Text
    var
        Token: JsonToken;
    begin
        if JObject.Get(PropertyName, Token) then
            if not Token.AsValue().IsNull() then
                exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure ReadCode50(JObject: JsonObject; PropertyName: Text): Code[50]
    begin
        exit(CopyStr(UpperCase(ReadString(JObject, PropertyName)), 1, 50));
    end;

    local procedure ReadBoolean(JObject: JsonObject; PropertyName: Text): Boolean
    var
        Token: JsonToken;
        Value: Boolean;
    begin
        if not JObject.Get(PropertyName, Token) then
            exit(false);
        if Token.AsValue().IsNull() then
            exit(false);
        if not Evaluate(Value, Token.AsValue().AsText(), 9) then
            exit(false);
        exit(Value);
    end;
}
