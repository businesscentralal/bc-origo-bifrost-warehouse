namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Pick.Create message type.
/// Wraps BC's Create Pick flow (report "Whse.-Shipment - Create Pick", 7318) to generate a
/// Warehouse Activity Header (Type = Pick) from a Warehouse Shipment. After creation the
/// optional `assignedUserId` and `sortingMethod` are applied to the activity header (subject
/// to write-restrictions on those fields).
///
/// The actual report invocation is delegated to "Whse Pick Create Process ori" via Codeunit.Run
/// so report-time errors are caught and returned as Error responses without rolling back the
/// outer message-task transaction.
/// </summary>

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;

using Origo.Bifrost;

codeunit 10078412 "Whse Pick Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
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
        exit(Database::"Warehouse Shipment Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Creates a Warehouse Pick from a Warehouse Shipment (BC report 7318 "Whse.-Shipment - Create Pick").');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create pick, pick list, picking, pick the goods, pick for shipment, pick the items, pick for the order, picking list', Comment = 'is-IS=stofna tínslu, tínslulisti, tína, tína vörur, tínsla fyrir afhendingu, tína vörur, tína í pöntun, tínslulisti fyrir pöntun';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Creates a Warehouse Pick from an existing shipment; use Warehouse.Pick.Register after quantities are picked.', Comment = 'is-IS=Stofnar tínslu úr fyrirliggjandi afhendingu; notaðu Warehouse.Pick.Register eftir að vörur hafa verið tíndar.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Shipment from which the pick is created: its SystemId or No.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Target := Parts.RecordTarget('Warehouse Shipment Header', 'systemId, recordSystemId, id, whseShipmentNo, shipmentNo, no');
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
        Fields.Add(ContractMgt.ResponseField('whseShipmentNo', 'string', 'Source Warehouse Shipment number.'));
        Fields.Add(ContractMgt.ResponseField('pickNo', 'string', 'Created Warehouse Pick number.'));
        Fields.Add(ContractMgt.ResponseField('pickSystemId', 'string', 'Created Warehouse Pick SystemId.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Warehouse location code.'));
        Fields.Add(ContractMgt.ResponseField('assignedUserId', 'string', 'Assigned user.'));
        Fields.Add(ContractMgt.ResponseField('sortingMethod', 'string', 'Sorting method.'));
        Fields.Add(ContractMgt.ResponseField('totalPickLines', 'integer', 'Number of pick lines.'));
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
        Parts.AddLookupErrors(Errors, 'Warehouse Shipment Header');
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, 'A sortingMethod or report option is not valid.', 'Use a valid sorting method and leave unsupported report options false.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'No Warehouse Pick was created for the shipment.', 'Ensure the shipment has lines requiring a pick and no pick already exists.'));
        Parts.AddBusinessCentralError(Errors, 'missing warehouse setup, no quantities to pick or report validation failure');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Creates Warehouse Activity Header and Line records of type Pick and applies optional activity fields.', 'BIFROST Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Create', 'Use it first when the Warehouse Shipment does not exist.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it after picking to register the created pick.'));
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
    begin
        exit(false);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Creates a Warehouse Pick from an existing Warehouse Shipment using BC report 7318 and applies optional activity fields.';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := '';
        exit(false);
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
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
        FieldWriteRestrictedErr: Label 'Field %1 is restricted for write on table %2.', Comment = '%1 = field caption, %2 = table caption', Locked = true;
        UnsupportedOptionErr: Label '%1 = true is not supported by this API version. Only the BC defaults (false) are honoured.', Comment = '%1 = option name', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        RequestJson := Argument.GetRequestJson();

        if not FindWhseShipmentHeader(Argument, WhseShipmentHeader) then
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

        // setBreakbulkFilter / doNotFillQtyToHandle are request-page-only on BC report 7318.
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
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Pick Create Process ori", WhseShipmentHeader)
        else
            if not Codeunit.Run(Codeunit::"Whse Pick Create Process ori", WhseShipmentHeader) then begin
                Argument.RespondWithError(GetLastErrorText());
                exit;
            end;

        // Locate the activity header that was created. Match the latest pick whose source line
        // points at this Warehouse Shipment.
        if not FindCreatedPick(WhseShipmentHeader."No.", WarehouseActivityHeader) then begin
            Argument.RespondWithError(StrSubstNo(NoPickCreatedErr(), WhseShipmentHeader."No."));
            exit;
        end;

        if HasAssignedUserId then begin
            WarehouseActivityHeader.Validate("Assigned User ID", AssignedUserIdValue);
            WarehouseActivityHeader.Modify(true);
        end;
        if HasSortingMethod then begin
            WarehouseActivityHeader.Validate("Sorting Method", SortingMethodValue);
            WarehouseActivityHeader.Modify(true);
        end;

        BuildResponse(WhseShipmentHeader, WarehouseActivityHeader, ResponseJson);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindWhseShipmentHeader(var Argument: Record "Message Argument ori"; var WhseShipmentHeader: Record "Warehouse Shipment Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
    begin
        // Every identifier sent is tried; the shared lookup answers missing, not found and conflicts.
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Shipment Header", 'guid|no', 'systemId=guid,recordSystemId=guid,id=guid,whseShipmentNo=no,shipmentNo=no,no=no', FoundSystemId) then
            exit(false);
        exit(WhseShipmentHeader.GetBySystemId(FoundSystemId));
    end;

    local procedure FindCreatedPick(WhseShipmentNo: Code[20]; var WarehouseActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        WarehouseActivityLine: Record "Warehouse Activity Line";
    begin
        // The activity line "Whse. Document No." points back to the source Warehouse Shipment "No.".
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::Pick);
        WarehouseActivityLine.SetRange("Whse. Document Type", WarehouseActivityLine."Whse. Document Type"::Shipment);
        WarehouseActivityLine.SetRange("Whse. Document No.", WhseShipmentNo);
        WarehouseActivityLine.SetCurrentKey("No.");
        if not WarehouseActivityLine.FindLast() then
            exit(false);
        WarehouseActivityHeader.SetRange(Type, WarehouseActivityHeader.Type::Pick);
        WarehouseActivityHeader.SetRange("No.", WarehouseActivityLine."No.");
        exit(WarehouseActivityHeader.FindFirst());
    end;

    local procedure BuildResponse(WhseShipmentHeader: Record "Warehouse Shipment Header"; WarehouseActivityHeader: Record "Warehouse Activity Header"; var ResponseJson: JsonObject)
    var
        WarehouseActivityLine: Record "Warehouse Activity Line";
        TotalQtyToHandle: Decimal;
        TotalLines: Integer;
        SuccessMsg: Label 'Warehouse Pick %1 created from Shipment %2 with %3 lines.', Comment = '%1 = pick no., %2 = shipment no., %3 = line count', Locked = true;
    begin
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::Pick);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        TotalLines := WarehouseActivityLine.Count();
        WarehouseActivityLine.CalcSums("Qty. to Handle");
        TotalQtyToHandle := WarehouseActivityLine."Qty. to Handle";

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('whseShipmentNo', WhseShipmentHeader."No.");
        ResponseJson.Add('pickNo', WarehouseActivityHeader."No.");
        ResponseJson.Add('pickSystemId', Format(WarehouseActivityHeader.SystemId, 0, 4));
        ResponseJson.Add('locationCode', WarehouseActivityHeader."Location Code");
        ResponseJson.Add('assignedUserId', WarehouseActivityHeader."Assigned User ID");
        ResponseJson.Add('sortingMethod', SortingMethodName(WarehouseActivityHeader."Sorting Method"));
        ResponseJson.Add('totalPickLines', TotalLines);
        ResponseJson.Add('totalQtyToHandle', TotalQtyToHandle);
        ResponseJson.Add('message', StrSubstNo(SuccessMsg, WarehouseActivityHeader."No.", WhseShipmentHeader."No.", TotalLines));
    end;

    local procedure SortingMethodName(SortingMethod: Enum "Whse. Activity Sorting Method") Name: Text
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        Index: Integer;
        DefaultNameTok: Label 'None', Locked = true;
    begin
        // The first ordinal of "Whse. Activity Sorting Method" has a blank/whitespace caption
        // in some BC builds. Normalise that to "None" so JSON consumers never see a single space.
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

    local procedure NoPickCreatedErr() Result: Text
    var
        Err: Label 'No Warehouse Pick was created for Warehouse Shipment %1. There may be nothing to pick, the shipment may not require a pick, or the pick may already exist.', Comment = '%1 = shipment no.', Locked = true;
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
