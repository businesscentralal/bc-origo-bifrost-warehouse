namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Putaway.Register message type.
/// Registers a Warehouse Put-away using BC's `Whse.-Activity-Register` codeunit. Gated by
/// `BIFROST WhsePost ori`. After registration the put-away header moves to history and the
/// bin contents are updated for the receive bins and storage bins involved.
/// </summary>

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;
using Microsoft.Warehouse.History;

using Origo.Bifrost;

codeunit 10078417 "Whse Putaway Register Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
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
        exit('Registers a Warehouse Put-away (BC codeunit 7307 "Whse.-Activity-Register").');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'register put-away, goods put away, putaway done, confirm put-away', Comment = 'is-IS=skrá frágang, vörum gengið frá, frágangi lokið, staðfesta frágang';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Registers an existing Warehouse Put-away and updates bin contents.', Comment = 'is-IS=Óafturkræft. Skráir fyrirliggjandi frágang og uppfærir innihald hólfa.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Put-away to register: its SystemId or put-away number.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Target := Parts.ActivityTarget('Warehouse Put-away', 'putawayNo');
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('putawayNo', 'string', 'Registered put-away number.'));
        Fields.Add(ContractMgt.ResponseField('linesRegistered', 'integer', 'Number of put-away lines registered.'));
        Fields.Add(ContractMgt.ResponseField('totalQtyRegistered', 'number', 'Total quantity registered.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseReceiptNo', 'string', 'Source Posted Warehouse Receipt number when available.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseReceiptSystemId', 'string', 'Source Posted Warehouse Receipt SystemId when available.'));
        Fields.Add(ContractMgt.ResponseField('receiptLines', 'array', 'Source posted receipt line summaries.'));
        Fields.Add(ContractMgt.ResponseField('registeredPutawayNo', 'string', 'Registered activity number when available.'));
        Fields.Add(ContractMgt.ResponseField('registeredPutawaySystemId', 'string', 'Registered activity SystemId when available.'));
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
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'The Warehouse Put-away has no lines or the identified activity is not a Put-away.', 'Send a Warehouse Put-away with lines.'));
        Parts.AddBusinessCentralError(Errors, 'invalid quantities or warehouse activity state');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Registers the Warehouse Put-away, moves it to history and updates bin contents.', 'BIFROST WhsePost ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Create', 'Use it first when a Warehouse Put-away does not exist.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'Use it to post the receipt before creating a put-away.'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Irreversibly registers a Warehouse Put-away and updates the involved bin contents.';
        exit(true);
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
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        RegisteredWhseActivityHdr: Record "Registered Whse. Activity Hdr.";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        ReceiptLinesArray: JsonArray;
        PutawayNoBeforeRun: Code[20];
        SourcePostedReceiptNo: Code[20];
        LinesInPutawayBeforeRun: Integer;
        TotalQtyToHandleBeforeRun: Decimal;
        NoLinesErr: Label 'Warehouse Put-away %1 has no lines.', Comment = '%1 = put-away no.', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;

        RequestJson := Argument.GetRequestJson();
        if not FindWarehousePutaway(Argument, WarehouseActivityHeader) then
            exit;

        PutawayNoBeforeRun := WarehouseActivityHeader."No.";

        // Snapshot the put-away's lines so we can summarise after the header moves to history.
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("No.", PutawayNoBeforeRun);
        if WarehouseActivityLine.IsEmpty() then begin
            Argument.RespondWithError(StrSubstNo(NoLinesErr, PutawayNoBeforeRun));
            exit;
        end;
        LinesInPutawayBeforeRun := WarehouseActivityLine.Count();
        WarehouseActivityLine.CalcSums("Qty. to Handle");
        TotalQtyToHandleBeforeRun := WarehouseActivityLine."Qty. to Handle";

        // Source Posted Whse. Receipt is on the activity line as "Whse. Document No." when the
        // put-away was created from a Posted Whse. Receipt.
        WarehouseActivityLine.FindFirst();
        if WarehouseActivityLine."Whse. Document Type" = WarehouseActivityLine."Whse. Document Type"::Receipt then
            SourcePostedReceiptNo := WarehouseActivityLine."Whse. Document No.";

        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse.-Activity-Register", WarehouseActivityLine)
        else
            if not Codeunit.Run(Codeunit::"Whse.-Activity-Register", WarehouseActivityLine) then begin
                Argument.RespondWithError(GetLastErrorText());
                exit;
            end;

        BuildReceiptLinesArray(SourcePostedReceiptNo, ReceiptLinesArray);

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('putawayNo', PutawayNoBeforeRun);
        ResponseJson.Add('linesRegistered', LinesInPutawayBeforeRun);
        ResponseJson.Add('totalQtyRegistered', TotalQtyToHandleBeforeRun);
        if SourcePostedReceiptNo <> '' then begin
            ResponseJson.Add('postedWhseReceiptNo', SourcePostedReceiptNo);
            if PostedWhseReceiptHeader.Get(SourcePostedReceiptNo) then
                ResponseJson.Add('postedWhseReceiptSystemId', Format(PostedWhseReceiptHeader.SystemId, 0, 4));
        end;
        ResponseJson.Add('receiptLines', ReceiptLinesArray);

        RegisteredWhseActivityHdr.SetRange("Whse. Activity No.", PutawayNoBeforeRun);
        if RegisteredWhseActivityHdr.FindLast() then begin
            ResponseJson.Add('registeredPutawayNo', RegisteredWhseActivityHdr."No.");
            ResponseJson.Add('registeredPutawaySystemId', Format(RegisteredWhseActivityHdr.SystemId, 0, 4));
        end;

        ResponseJson.Add('message', BuildSuccessMessage(PutawayNoBeforeRun, LinesInPutawayBeforeRun, SourcePostedReceiptNo));

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindWarehousePutaway(var Argument: Record "Message Argument ori"; var WarehouseActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
        DocumentKind: Text;
        NotPutawayErr: Label 'Warehouse Activity %1 is not of Type Put-away.', Comment = '%1 = activity no.', Locked = true;
    begin
        // Every identifier sent is tried; the shared lookup answers missing, not found and conflicts.
        // A number is looked up as Type = Put-away; a SystemId may name any activity, so the type is checked after.
        DocumentKind := 'doc' + Format(WarehouseActivityHeader.Type::"Put-away".AsInteger(), 0, 9) + ':putawayNo';
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Activity Header", 'guid|' + DocumentKind, 'systemId=guid,recordSystemId=guid,id=guid,putawayNo=' + DocumentKind + ',no=' + DocumentKind, FoundSystemId) then
            exit(false);
        WarehouseActivityHeader.GetBySystemId(FoundSystemId);
        if WarehouseActivityHeader.Type <> WarehouseActivityHeader.Type::"Put-away" then begin
            Argument.RespondWithError(StrSubstNo(NotPutawayErr, WarehouseActivityHeader."No."));
            exit(false);
        end;
        exit(true);
    end;

    local procedure BuildReceiptLinesArray(PostedWhseReceiptNo: Code[20]; var ReceiptLinesArray: JsonArray)
    var
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        LineObject: JsonObject;
    begin
        if PostedWhseReceiptNo = '' then
            exit;
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptNo);
        if not PostedWhseReceiptLine.FindSet() then
            exit;
        repeat
            Clear(LineObject);
            LineObject.Add('postedWhseReceiptNo', PostedWhseReceiptLine."No.");
            LineObject.Add('lineNo', PostedWhseReceiptLine."Line No.");
            LineObject.Add('sourceDocument', PostedWhseReceiptLine."Source Document".Names().Get(PostedWhseReceiptLine."Source Document".Ordinals().IndexOf(PostedWhseReceiptLine."Source Document".AsInteger())));
            LineObject.Add('sourceNo', PostedWhseReceiptLine."Source No.");
            LineObject.Add('sourceLineNo', PostedWhseReceiptLine."Source Line No.");
            LineObject.Add('itemNo', PostedWhseReceiptLine."Item No.");
            LineObject.Add('qty', PostedWhseReceiptLine.Quantity);
            LineObject.Add('qtyPutAway', PostedWhseReceiptLine."Qty. Put Away");
            LineObject.Add('qtyOutstanding', PostedWhseReceiptLine.Quantity - PostedWhseReceiptLine."Qty. Put Away");
            LineObject.Add('status', Format(PostedWhseReceiptLine.Status));
            ReceiptLinesArray.Add(LineObject);
        until PostedWhseReceiptLine.Next() = 0;
    end;

    local procedure BuildSuccessMessage(PutawayNo: Code[20]; LinesRegistered: Integer; SourcePostedReceiptNo: Code[20]): Text
    var
        FromReceiptMsg: Label 'Warehouse Put-away %1 (%2 lines) registered against Posted Whse. Receipt %3.', Comment = '%1 = put-away no., %2 = line count, %3 = posted receipt no.', Locked = true;
        StandaloneMsg: Label 'Warehouse Put-away %1 (%2 lines) registered.', Comment = '%1 = put-away no., %2 = line count', Locked = true;
    begin
        if SourcePostedReceiptNo <> '' then
            exit(StrSubstNo(FromReceiptMsg, PutawayNo, LinesRegistered, SourcePostedReceiptNo));
        exit(StrSubstNo(StandaloneMsg, PutawayNo, LinesRegistered));
    end;
}
