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

codeunit 10078414 "Whse Pick Register Impl ori" implements "Msg Interface ori", "Msg Discovery ori"
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
    begin
        exit(GetDescription());
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure GetMessageHelpAsMarkdownDocument(var Argument: Record "Message Argument ori")
    var
        HelpCodeunit: Codeunit "Whse Pick Register Help ori";
    begin
        Argument.SetResponseMarkdown(HelpCodeunit.GetHelpText());
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
