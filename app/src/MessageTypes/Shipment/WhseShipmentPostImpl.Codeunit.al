namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Shipment.Post message type.
/// Posts a Warehouse Shipment using BC's Whse.-Post Shipment (codeunit 5763). Always gated by
/// `BIFROST WhsePost ori`. When `invoice = true`, also gated by `BIFROST WhseInv ori` because the
/// invoice pass writes to the G/L Register.
/// </summary>

using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Posting;

using Origo.Bifrost;

codeunit 10078407 "Whse Shipment Post Impl ori" implements "Msg Interface ori", "Msg Discovery ori"
{
    Access = Internal;
    procedure IsEnabled(): Boolean
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
    begin
        if not WhseShipmentHeader.WritePermission() then
            exit(false);
        exit(WhsePostingGate.HasPostingPermission());
    end;

    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Warehouse Shipment Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Posts a Warehouse Shipment (ship, optionally invoice).');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'post warehouse shipment, ship goods, goods left the warehouse, dispatch goods, send the goods out', Comment = 'is-IS=bóka vöruhúsaafhendingu, afhenda vörur, vörur farnar úr vöruhúsi, senda vörur út';
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
        HelpCodeunit: Codeunit "Whse Shipment Post Help ori";
    begin
        Argument.SetResponseMarkdown(HelpCodeunit.GetHelpText());
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        WhsePostShipment: Codeunit "Whse.-Post Shipment";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        Dispatcher: Codeunit "Dispatcher ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        PostedDocsArray: JsonArray;
        Invoice: Boolean;
        NoLinesToPostErr: Label 'Warehouse Shipment %1 has no lines to post.', Comment = '%1 = Whse. Shipment No.', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;

        RequestJson := Argument.GetRequestJson();
        if not Dispatcher.TryReadBoolean(Argument, RequestJson, 'invoice', false, Invoice) then
            exit;

        if Invoice then
            if not WhsePostingGate.AssertCanInvoice(Argument) then
                exit;

        if not FindWhseShipmentHeader(Argument, WhseShipmentHeader) then
            exit;

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if WhseShipmentLine.IsEmpty() then begin
            Argument.RespondWithError(StrSubstNo(NoLinesToPostErr, WhseShipmentHeader."No."));
            exit;
        end;
        WhseShipmentLine.FindFirst();

        WhsePostShipment.SetPostingSettings(Invoice);
        if not WhsePostShipment.Run(WhseShipmentLine) then begin
            Argument.RespondWithError(GetLastErrorText());
            exit;
        end;

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('shipmentNo', WhseShipmentHeader."No.");
        ResponseJson.Add('invoice', Invoice);

        if FindPostedWhseShipment(WhseShipmentHeader."No.", PostedWhseShipmentHeader) then begin
            ResponseJson.Add('postedWhseShipmentNo', PostedWhseShipmentHeader."No.");
            ResponseJson.Add('postedWhseShipmentSystemId', Format(PostedWhseShipmentHeader.SystemId, 0, 4));
            AppendPostedSourceDocuments(PostedWhseShipmentHeader."No.", PostedDocsArray);
        end;
        ResponseJson.Add('postedDocuments', PostedDocsArray);

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindWhseShipmentHeader(var Argument: Record "Message Argument ori"; var WhseShipmentHeader: Record "Warehouse Shipment Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
    begin
        // Every identifier supplied is tried; the shared lookup reads the request JSON itself.
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Shipment Header", 'guid|no', 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', FoundSystemId) then
            exit(false);
        exit(WhseShipmentHeader.GetBySystemId(FoundSystemId));
    end;

    local procedure FindPostedWhseShipment(SourceShipmentNo: Code[20]; var PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header"): Boolean
    begin
        PostedWhseShipmentHeader.SetCurrentKey("Whse. Shipment No.");
        PostedWhseShipmentHeader.SetRange("Whse. Shipment No.", SourceShipmentNo);
        exit(PostedWhseShipmentHeader.FindLast());
    end;

    local procedure AppendPostedSourceDocuments(PostedWhseShipmentNo: Code[20]; var PostedDocsArray: JsonArray)
    var
        PostedWhseShipmentLine: Record "Posted Whse. Shipment Line";
        DocJson: JsonObject;
        SeenKeys: List of [Text];
        DedupKey: Text;
    begin
        // Each Posted Whse. Shipment Line records the resulting posted source document
        // (e.g. Posted Sales Shipment, Posted Transfer Shipment) via Posted Source Document + Posted Source No.
        // Multiple lines can map to the same posted document — de-duplicate by composite key.
        PostedWhseShipmentLine.SetRange("No.", PostedWhseShipmentNo);
        PostedWhseShipmentLine.SetLoadFields("Posted Source Document", "Posted Source No.", "Source Document", "Source No.");
        if PostedWhseShipmentLine.FindSet() then
            repeat
                DedupKey := Format(PostedWhseShipmentLine."Posted Source Document") + '|' + PostedWhseShipmentLine."Posted Source No.";
                if not SeenKeys.Contains(DedupKey) then begin
                    SeenKeys.Add(DedupKey);
                    Clear(DocJson);
                    DocJson.Add('postedSourceDocument', Format(PostedWhseShipmentLine."Posted Source Document"));
                    DocJson.Add('postedSourceNo', PostedWhseShipmentLine."Posted Source No.");
                    DocJson.Add('sourceDocument', Format(PostedWhseShipmentLine."Source Document"));
                    DocJson.Add('sourceNo', PostedWhseShipmentLine."Source No.");
                    PostedDocsArray.Add(DocJson);
                end;
            until PostedWhseShipmentLine.Next() = 0;
    end;
}
