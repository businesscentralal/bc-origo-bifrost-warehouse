namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Receipt.Post message type.
/// Posts a Warehouse Receipt using BC's Whse.-Post Receipt (codeunit 5760). Gated by
/// `BIFROST WhsePost ori`. Unlike Warehouse Shipment, there is no `invoice` step — the
/// receipt only performs the receive and creates Posted Whse. Receipt + the underlying
/// posted source documents (e.g. Posted Purchase Receipt, Posted Return Shipment, Posted
/// Transfer Receipt). Invoicing on the source document is a separate later action.
/// Optional lines[] set Qty. to Receive per line (#54); the quantities and the posting run in this
/// codeunit's own OnRun inside Codeunit.Run, so a failure leaves the quantities unchanged.
/// </summary>

using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Posting;

using Origo.Bifrost;

codeunit 10078410 "Whse Receipt Post Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        Context: Codeunit "Whse Write Context ori";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        WhsePostReceipt: Codeunit "Whse.-Post Receipt";
        Payload: JsonObject;
        Token: JsonToken;
        ReceiptNo: Code[20];
        MissingPayloadErr: Label 'The receipt posting payload was empty.', Comment = 'is-IS=Gögnin til að bóka móttöku voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Payload.Get('receiptNo', Token);
        ReceiptNo := CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(ReceiptNo));
        Payload.Get('lines', Token);
        DocLineQty.ApplyQuantities(false, ReceiptNo, Token.AsArray());
        WhseReceiptLine.SetRange("No.", ReceiptNo);
        WhseReceiptLine.FindFirst();
        // The outer Codeunit.Run commits once, or the caller does under Omit Commit.
        WhsePostReceipt.SetSuppressCommit(true);
        WhsePostReceipt.Run(WhseReceiptLine);
    end;

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
    var
        DescriptionLbl: Label 'Posts a Warehouse Receipt (receive), optionally with a quantity per line.', Comment = 'is-IS=Bókar vöruhúsamóttöku (móttöku), valfrjálst með magni á hverja línu.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'receive, goods received, goods came in, the goods came in, warehouse receipt, post receipt', Comment = 'is-IS=móttaka, vörumóttaka, vörur komnar, vörur komu, vöruhúsamóttaka, bóka vöruhúsamóttöku';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Posts an existing Warehouse Receipt; use Warehouse.Receipt.PreviewPost to inspect the result first.', Comment = 'is-IS=Óafturkræft. Bókar fyrirliggjandi vöruhúsamóttöku; notaðu Warehouse.Receipt.PreviewPost til að skoða niðurstöðuna fyrst.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Receipt to post: its SystemId or No.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the Warehouse Receipt Header.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the Warehouse Receipt Header.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.recordSystemId, data.id, data.receiptNo, data.no', 'guid or document no.', 'The identifier keys accepted for the Warehouse Receipt Header. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Optional per-line quantities to receive. Lines that are not listed keep their current Qty. to Receive.'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Warehouse receipt line number (inside lines).'));
        Parameters.Add(ContractMgt.Parameter('qtyToReceive', 'number', true, 'Quantity to receive on that line, from zero up to the outstanding quantity (inside lines).'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('receiptNo', 'string', 'The posted Warehouse Receipt source number.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseReceiptNo', 'string', 'Posted Warehouse Receipt number when available.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseReceiptSystemId', 'string', 'Posted Warehouse Receipt SystemId when available.'));
        Fields.Add(ContractMgt.ResponseField('postedDocuments', 'array', 'Distinct posted source-document summaries.'));
        Fields.Add(ContractMgt.ResponseField('lines', 'array', 'Per receipt line: lineNo, itemNo, quantityPosted and quantityRemaining on the receipt after the post.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddDocumentPostErrors(Errors, 'Warehouse Receipt Header', 'systemId, recordSystemId, id, receiptNo, no', 'qtyToReceive', false);
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Sets the listed quantities to receive and posts the Warehouse Receipt; Business Central commits the posting. Source documents are received but not invoiced.', 'BIFROST WhsePost ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.PreviewPost', 'Use it to inspect predicted entries without committing before posting.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Create', 'Use it after posting when the received goods require put-away.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PostedDocument.Get', 'Use it to read the posted warehouse receipt.'));
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.InboundWorkflow(Workflow);
        exit(true);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Receive 3 of 5 on line 10000 of receipt RE000001',
            '{"receiptNo":"RE000001","lines":[{"lineNo":10000,"qtyToReceive":3}]}',
            '{"status":"Success","receiptNo":"RE000001","postedWhseReceiptNo":"R_000001","postedWhseReceiptSystemId":"6f1c1d2e-0000-0000-0000-000000000006","postedDocuments":[{"postedSourceDocument":"Posted Receipt","postedSourceNo":"107001","sourceDocument":"Purchase Order","sourceNo":"106001"}],"lines":[{"lineNo":10000,"itemNo":"1896-S","quantityPosted":3,"quantityRemaining":2}]}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Irreversibly posts a Warehouse Receipt, and Business Central commits the posting. Optional lines set Qty. to Receive per line first; lines that are not listed keep their value, and a quantity above the outstanding quantity is refused. Source-document invoicing is a separate later action.', Comment = 'is-IS=Bókar vöruhúsamóttöku óafturkræft og Business Central staðfestir bókunina. Valfrjálsar línur setja fyrst magn til móttöku á hverja línu; línur sem eru ekki taldar upp halda gildi sínu og magni umfram útistandandi magn er hafnað. Reikningsfærsla upprunaskjala er sérstök aðgerð síðar.';
    begin
        Overview := OverviewLbl;
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
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        Context: Codeunit "Whse Write Context ori";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        Payload: JsonObject;
        PostedDocsArray: JsonArray;
        PlannedLines: JsonArray;
        LineSummary: JsonArray;
        NoLinesToPostErr: Label 'Warehouse Receipt %1 has no lines to post.', Comment = '%1 = Whse. Receipt No., is-IS=Vöruhúsamóttaka %1 hefur engar línur til bókunar.';
        NothingLbl: Label 'Every line of warehouse receipt %1 would receive zero.', Comment = '%1 = receipt no., is-IS=Hver lína vöruhúsamóttöku %1 myndi taka á móti núlli.';
        NothingNextStepLbl: Label 'Set a quantity above zero on at least one line.', Comment = 'is-IS=Settu magn yfir núlli á að minnsta kosti eina línu.';
        ProblemsLbl: Label 'Nothing was posted.', Comment = 'is-IS=Ekkert var bókað.';
    begin
        Context.Reset();
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;

        if not WhseRecordLookup.TryReadIdentifiers(Argument, 'systemId=guid,recordSystemId=guid,id=guid,receiptNo=no,no=no', RequestJson) then
            exit;
        // An unknown key is answered together with the lookup and line problems, so it does not hide them.
        RefuseUnknownKeys(RequestJson, Argument);

        if not FindWhseReceiptHeader(Argument, WhseReceiptHeader) then
            exit;

        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        if WhseReceiptLine.IsEmpty() then begin
            if Argument.HasCollectedErrors() then begin
                Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
                exit;
            end;
            Argument.RespondWithError(StrSubstNo(NoLinesToPostErr, WhseReceiptHeader."No."));
            exit;
        end;

        DocLineQty.ReadLines(RequestJson, Argument, false, WhseReceiptHeader."No.", PlannedLines);
        if not Argument.HasCollectedErrors() then
            if not DocLineQty.HasQuantityToPost(false, WhseReceiptHeader."No.", PlannedLines) then
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NothingLbl, WhseReceiptHeader."No."), 'lines', '', '', NothingNextStepLbl);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        LineSummary := DocLineQty.LineSummary(false, WhseReceiptHeader."No.", PlannedLines);

        Payload.Add('receiptNo', WhseReceiptHeader."No.");
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Receipt Post Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Receipt Post Impl ori") then begin
                Context.Reset();
                Argument.RespondWithError(GetLastErrorText());
                exit;
            end;
        Context.Reset();

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('receiptNo', WhseReceiptHeader."No.");

        if FindPostedWhseReceipt(WhseReceiptHeader."No.", PostedWhseReceiptHeader) then begin
            ResponseJson.Add('postedWhseReceiptNo', PostedWhseReceiptHeader."No.");
            ResponseJson.Add('postedWhseReceiptSystemId', Format(PostedWhseReceiptHeader.SystemId, 0, 4));
            AppendPostedSourceDocuments(PostedWhseReceiptHeader."No.", PostedDocsArray);
        end;
        ResponseJson.Add('postedDocuments', PostedDocsArray);
        ResponseJson.Add('lines', LineSummary);

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['systemId', 'recordSystemId', 'id', 'receiptNo', 'no', 'lines']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
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
