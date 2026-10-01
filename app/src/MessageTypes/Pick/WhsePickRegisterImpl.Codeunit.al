namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Pick.Register message type.
/// Registers a Warehouse Pick using BC's `Whse.-Activity-Register` codeunit. Gated by
/// `BIFROST WhsePost ori`. After registration the source `Warehouse Shipment Line` rows
/// receive the picked quantity and the pick header moves to history.
/// </summary>

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;
using Microsoft.Warehouse.Document;

using Origo.Bifrost;

codeunit 10078414 "Whse Pick Register Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    procedure IsEnabled(): Boolean
    var
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
    begin
        exit(WhsePostingGate.HasPostingPermission());
    end;
    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Warehouse Activity Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Registers a Warehouse Pick (BC codeunit 7307 "Whse.-Activity-Register").');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'register pick, goods picked, picking done, confirm picking', Comment = 'is-IS=skrá tínslu, vörur tíndar, tínslu lokið, staðfesta tínslu';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Registers an existing Warehouse Pick and updates shipment quantities.', Comment = 'is-IS=Óafturkræft. Skráir fyrirliggjandi tínslu og uppfærir magn í afhendingu.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Pick to register: its SystemId or pick number.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Target := Parts.ActivityTarget('Warehouse Pick', 'pickNo');
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    begin
        exit(false);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('pickNo', 'string', 'Registered pick number.'));
        Fields.Add(ContractMgt.ResponseField('linesRegistered', 'integer', 'Number of pick lines registered.'));
        Fields.Add(ContractMgt.ResponseField('totalQtyRegistered', 'number', 'Total quantity registered.'));
        Fields.Add(ContractMgt.ResponseField('shipmentNo', 'string', 'Source Warehouse Shipment number when available.'));
        Fields.Add(ContractMgt.ResponseField('shipmentSystemId', 'string', 'Source Warehouse Shipment SystemId when available.'));
        Fields.Add(ContractMgt.ResponseField('shipmentLines', 'array', 'Source shipment line summaries.'));
        Fields.Add(ContractMgt.ResponseField('registeredPickNo', 'string', 'Registered activity number when available.'));
        Fields.Add(ContractMgt.ResponseField('registeredPickSystemId', 'string', 'Registered activity SystemId when available.'));
        Fields.Add(ContractMgt.ResponseField('message', 'string', 'Human-readable result.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddLookupErrors(Errors, 'Warehouse Activity Header');
        Parts.AddPermissionError(Errors, 'BIFROST WhsePost ori');
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'The Warehouse Pick has no lines or the identified activity is not a Pick.', 'Send a Warehouse Pick with lines.'));
        Parts.AddBusinessCentralError(Errors, 'invalid quantities or warehouse activity state');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Registers the Warehouse Pick, moves it to history and updates the source shipment quantities.', 'BIFROST WhsePost ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Create', 'Use it first when a Warehouse Pick does not exist.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Post', 'Use it after registering the pick to post the shipment.'));
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
        Overview := 'Irreversibly registers a Warehouse Pick and updates its source Warehouse Shipment quantities.';
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
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        RegisteredWhseActivityHdr: Record "Registered Whse. Activity Hdr.";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        ShipmentLinesArray: JsonArray;
        PickNoBeforeRun: Code[20];
        SourceShipmentNo: Code[20];
        LinesInPickBeforeRun: Integer;
        TotalQtyToHandleBeforeRun: Decimal;
        NoLinesErr: Label 'Warehouse Pick %1 has no lines.', Comment = '%1 = pick no.', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;

        RequestJson := Argument.GetRequestJson();
        if not FindWarehousePick(Argument, WarehouseActivityHeader) then
            exit;

        PickNoBeforeRun := WarehouseActivityHeader."No.";

        // Snapshot the pick's lines so we can summarise after the header moves to history.
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::Pick);
        WarehouseActivityLine.SetRange("No.", PickNoBeforeRun);
        if WarehouseActivityLine.IsEmpty() then begin
            Argument.RespondWithError(StrSubstNo(NoLinesErr, PickNoBeforeRun));
            exit;
        end;
        LinesInPickBeforeRun := WarehouseActivityLine.Count();
        WarehouseActivityLine.CalcSums("Qty. to Handle");
        TotalQtyToHandleBeforeRun := WarehouseActivityLine."Qty. to Handle";

        // Source Warehouse Shipment is on the activity line as "Whse. Document No." when the
        // pick was created from a Warehouse Shipment.
        WarehouseActivityLine.FindFirst();
        if WarehouseActivityLine."Whse. Document Type" = WarehouseActivityLine."Whse. Document Type"::Shipment then
            SourceShipmentNo := WarehouseActivityLine."Whse. Document No.";

        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse.-Activity-Register", WarehouseActivityLine)
        else
            if not Codeunit.Run(Codeunit::"Whse.-Activity-Register", WarehouseActivityLine) then begin
                Argument.RespondWithError(GetLastErrorText());
                exit;
            end;

        BuildShipmentLinesArray(SourceShipmentNo, ShipmentLinesArray);

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('pickNo', PickNoBeforeRun);
        ResponseJson.Add('linesRegistered', LinesInPickBeforeRun);
        ResponseJson.Add('totalQtyRegistered', TotalQtyToHandleBeforeRun);
        if SourceShipmentNo <> '' then begin
            ResponseJson.Add('shipmentNo', SourceShipmentNo);
            if WhseShipmentHeader.Get(SourceShipmentNo) then
                ResponseJson.Add('shipmentSystemId', Format(WhseShipmentHeader.SystemId, 0, 4));
        end;
        ResponseJson.Add('shipmentLines', ShipmentLinesArray);

        RegisteredWhseActivityHdr.SetRange("Whse. Activity No.", PickNoBeforeRun);
        if RegisteredWhseActivityHdr.FindLast() then begin
            ResponseJson.Add('registeredPickNo', RegisteredWhseActivityHdr."No.");
            ResponseJson.Add('registeredPickSystemId', Format(RegisteredWhseActivityHdr.SystemId, 0, 4));
        end;

        ResponseJson.Add('message', BuildSuccessMessage(PickNoBeforeRun, LinesInPickBeforeRun, SourceShipmentNo));

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindWarehousePick(var Argument: Record "Message Argument ori"; var WarehouseActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
        DocumentKind: Text;
        NotPickErr: Label 'Warehouse Activity %1 is not of Type Pick.', Comment = '%1 = activity no.', Locked = true;
    begin
        // Every identifier sent is tried; the shared lookup answers missing, not found and conflicts.
        // A number is looked up as Type = Pick; a SystemId may name any activity, so the type is checked after.
        DocumentKind := 'doc' + Format(WarehouseActivityHeader.Type::Pick.AsInteger(), 0, 9) + ':pickNo';
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Activity Header", 'guid|' + DocumentKind, 'systemId=guid,recordSystemId=guid,id=guid,pickNo=' + DocumentKind + ',no=' + DocumentKind, FoundSystemId) then
            exit(false);
        WarehouseActivityHeader.GetBySystemId(FoundSystemId);
        if WarehouseActivityHeader.Type <> WarehouseActivityHeader.Type::Pick then begin
            Argument.RespondWithError(StrSubstNo(NotPickErr, WarehouseActivityHeader."No."));
            exit(false);
        end;
        exit(true);
    end;

    local procedure BuildShipmentLinesArray(WhseShipmentNo: Code[20]; var ShipmentLinesArray: JsonArray)
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        LineObject: JsonObject;
    begin
        if WhseShipmentNo = '' then
            exit;
        WhseShipmentLine.SetRange("No.", WhseShipmentNo);
        if not WhseShipmentLine.FindSet() then
            exit;
        repeat
            Clear(LineObject);
            LineObject.Add('shipmentNo', WhseShipmentLine."No.");
            LineObject.Add('lineNo', WhseShipmentLine."Line No.");
            LineObject.Add('sourceDocument', Format(WhseShipmentLine."Source Document"));
            LineObject.Add('sourceNo', WhseShipmentLine."Source No.");
            LineObject.Add('sourceLineNo', WhseShipmentLine."Source Line No.");
            LineObject.Add('itemNo', WhseShipmentLine."Item No.");
            LineObject.Add('qty', WhseShipmentLine.Quantity);
            LineObject.Add('qtyPicked', WhseShipmentLine."Qty. Picked");
            LineObject.Add('qtyToShip', WhseShipmentLine."Qty. to Ship");
            LineObject.Add('qtyOutstanding', WhseShipmentLine."Qty. Outstanding");
            ShipmentLinesArray.Add(LineObject);
        until WhseShipmentLine.Next() = 0;
    end;

    local procedure BuildSuccessMessage(PickNo: Code[20]; LinesRegistered: Integer; SourceShipmentNo: Code[20]): Text
    var
        FromShipmentMsg: Label 'Warehouse Pick %1 (%2 lines) registered against Warehouse Shipment %3.', Comment = '%1 = pick no., %2 = line count, %3 = shipment no.', Locked = true;
        StandaloneMsg: Label 'Warehouse Pick %1 (%2 lines) registered.', Comment = '%1 = pick no., %2 = line count', Locked = true;
    begin
        if SourceShipmentNo <> '' then
            exit(StrSubstNo(FromShipmentMsg, PickNo, LinesRegistered, SourceShipmentNo));
        exit(StrSubstNo(StandaloneMsg, PickNo, LinesRegistered));
    end;
}
