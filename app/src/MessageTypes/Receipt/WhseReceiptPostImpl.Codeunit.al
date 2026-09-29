namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Receipt.Post message type.
/// Posts a Warehouse Receipt using BC's Whse.-Post Receipt (codeunit 5760). Gated by
/// `BIFROST WhsePost ori`. Unlike Warehouse Shipment, there is no `invoice` step — the
/// receipt only performs the receive and creates Posted Whse. Receipt + the underlying
/// posted source documents (e.g. Posted Purchase Receipt, Posted Return Shipment, Posted
/// Transfer Receipt). Invoicing on the source document is a separate later action.
/// </summary>

using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Posting;

using Origo.Bifrost;

codeunit 10078410 "Whse Receipt Post Impl ori" implements "Msg Interface ori", "Msg Discovery ori"
{
    Access = Internal;
    procedure IsEnabled(): Boolean
    var
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
    begin
        if not WarehouseReceiptHeader.WritePermission() then
            exit(false);
        exit(WhsePostingGate.HasPostingPermission());
    end;

    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Warehouse Receipt Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Posts a Warehouse Receipt (receive).');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'receive, goods received, goods came in, the goods came in, warehouse receipt, post receipt', Comment = 'is-IS=móttaka, vörumóttaka, vörur komnar, vörur komu, vöruhúsamóttaka, bóka vöruhúsamóttöku';
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
        HelpCodeunit: Codeunit "Whse Receipt Post Help ori";
    begin
        Argument.SetResponseMarkdown(HelpCodeunit.GetHelpText());
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WhsePostReceipt: Codeunit "Whse.-Post Receipt";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        PostedDocsArray: JsonArray;
        NoLinesToPostErr: Label 'Warehouse Receipt %1 has no lines to post.', Comment = '%1 = Whse. Receipt No.', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;

        RequestJson := Argument.GetRequestJson();

        if not FindWhseReceiptHeader(Argument, WhseReceiptHeader) then
            exit;

        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        if WhseReceiptLine.IsEmpty() then begin
            Argument.RespondWithError(StrSubstNo(NoLinesToPostErr, WhseReceiptHeader."No."));
            exit;
        end;
        WhseReceiptLine.FindFirst();

        if not WhsePostReceipt.Run(WhseReceiptLine) then begin
            Argument.RespondWithError(GetLastErrorText());
            exit;
        end;

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('receiptNo', WhseReceiptHeader."No.");

        if FindPostedWhseReceipt(WhseReceiptHeader."No.", PostedWhseReceiptHeader) then begin
            ResponseJson.Add('postedWhseReceiptNo', PostedWhseReceiptHeader."No.");
            ResponseJson.Add('postedWhseReceiptSystemId', Format(PostedWhseReceiptHeader.SystemId, 0, 4));
            AppendPostedSourceDocuments(PostedWhseReceiptHeader."No.", PostedDocsArray);
        end;
        ResponseJson.Add('postedDocuments', PostedDocsArray);

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindWhseReceiptHeader(var Argument: Record "Message Argument ori"; var WhseReceiptHeader: Record "Warehouse Receipt Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
    begin
        // Every identifier supplied is tried; the shared lookup reads the request JSON itself.
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Receipt Header", 'guid|no', 'systemId=guid,recordSystemId=guid,id=guid,receiptNo=no,no=no', FoundSystemId) then
            exit(false);
        exit(WhseReceiptHeader.GetBySystemId(FoundSystemId));
    end;

    local procedure FindPostedWhseReceipt(SourceReceiptNo: Code[20]; var PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header"): Boolean
    begin
        PostedWhseReceiptHeader.SetCurrentKey("Whse. Receipt No.");
        PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", SourceReceiptNo);
        exit(PostedWhseReceiptHeader.FindLast());
    end;

    local procedure AppendPostedSourceDocuments(PostedWhseReceiptNo: Code[20]; var PostedDocsArray: JsonArray)
    var
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        DocJson: JsonObject;
        SeenKeys: List of [Text];
        DedupKey: Text;
    begin
        // Each Posted Whse. Receipt Line records the resulting posted source document
        // (e.g. Posted Purchase Receipt, Posted Return Shipment, Posted Transfer Receipt)
        // via Posted Source Document + Posted Source No. — de-duplicate by composite key.
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptNo);
        PostedWhseReceiptLine.SetLoadFields("Posted Source Document", "Posted Source No.", "Source Document", "Source No.");
        if PostedWhseReceiptLine.FindSet() then
            repeat
                DedupKey := Format(PostedWhseReceiptLine."Posted Source Document") + '|' + PostedWhseReceiptLine."Posted Source No.";
                if not SeenKeys.Contains(DedupKey) then begin
                    SeenKeys.Add(DedupKey);
                    Clear(DocJson);
                    DocJson.Add('postedSourceDocument', Format(PostedWhseReceiptLine."Posted Source Document"));
                    DocJson.Add('postedSourceNo', PostedWhseReceiptLine."Posted Source No.");
                    DocJson.Add('sourceDocument', Format(PostedWhseReceiptLine."Source Document"));
                    DocJson.Add('sourceNo', PostedWhseReceiptLine."Source No.");
                    PostedDocsArray.Add(DocJson);
                end;
            until PostedWhseReceiptLine.Next() = 0;
    end;
}
