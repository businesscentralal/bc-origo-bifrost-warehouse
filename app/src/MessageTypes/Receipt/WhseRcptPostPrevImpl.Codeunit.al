namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Receipt.PreviewPost message type.
/// Simulates posting a Warehouse Receipt and returns the captured ledger entries
/// (Item Ledger, Value Entry, Posted Whse. Receipt, and any G/L impact) without committing.
/// The transaction is rolled back after capture via the Posting Preview Event Handler.
/// Uses Gen. Jnl.-Post Preview's headless SetContext+Run() entry point so the caller
/// can consume the captured entries instead of presenting them in BC's standard preview pages.
/// </summary>

using Microsoft.Finance.GeneralLedger.Preview;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.Navigate;
using Microsoft.Inventory.Ledger;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Posting;

using Origo.Bifrost;

codeunit 10078411 "Whse Rcpt Post Prev. Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;
    procedure IsEnabled(): Boolean
    begin
        // Preview does not consult the warehouse posting gate.
        exit(true);
    end;

    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Warehouse Receipt Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Simulates posting a Warehouse Receipt and returns predicted ledger entries (Item, Value, Posted Whse. Receipt) without committing.');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'preview warehouse receipt, simulate receipt, what would the receipt post', Comment = 'is-IS=forskoða vöruhúsamóttöku, herma móttöku, hvað myndi móttakan bóka';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Simulates receiving a Warehouse Receipt and rolls back; use Warehouse.Receipt.Post to commit the receipt.', Comment = 'is-IS=Lesaðgangur. Hermir móttöku vöruhúsamóttöku og afturkallar; notaðu Warehouse.Receipt.Post til að framkvæma móttökuna.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Receipt to preview: its SystemId or No.', false);
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
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Optional per-line quantities to receive in the preview, the same as Warehouse.Receipt.Post. They are rolled back with the preview. Needs write permission on warehouse receipt lines.'));
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
        Fields.Add(ContractMgt.ResponseField('entryCount', 'integer', 'Number of predicted ledger entries.'));
        Fields.Add(ContractMgt.ResponseField('glEntryCount', 'integer', 'Number of predicted G/L entries.'));
        Fields.Add(ContractMgt.ResponseField('rollback', 'boolean', 'Always true; the preview is rolled back.'));
        Fields.Add(ContractMgt.ResponseField('summary', 'string', 'Human-readable preview summary.'));
        Fields.Add(ContractMgt.ResponseField('receiptNo', 'string', 'Warehouse Receipt number.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Warehouse location code.'));
        Fields.Add(ContractMgt.ResponseField('sourceDocuments', 'array', 'Distinct source-document summaries.'));
        Fields.Add(ContractMgt.ResponseField('lcyCode', 'string', 'Local currency code.'));
        Fields.Add(ContractMgt.ResponseField('predictedNumbers', 'object', 'Predicted posted document numbers.'));
        Fields.Add(ContractMgt.ResponseField('totals', 'object', 'Preview totals.'));
        Fields.Add(ContractMgt.ResponseField('preview', 'array', 'Captured preview entries grouped by table.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'Posting preview cannot run inside a rollback chain (Omit Commit). Run this message type with Omit Commit set to false.', 'Call Dispatcher.Execute with OmitCommit = false, or use the HTTP/MCP API.'));
        Parts.AddLookupErrors(Errors, 'Warehouse Receipt Header');
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::NothingToPreview, 'The Warehouse Receipt has no lines or no quantities to post.', 'Add lines and quantities to receive.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidLine, 'A lineNo is not on the receipt, or qtyToReceive is negative or above the outstanding quantity.', 'Read the lines first, and read the outstanding quantity on the line and lower it.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::UnknownParameter, 'The request or a line contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PermissionDenied, 'lines was sent and the caller cannot write warehouse receipt lines.', 'Ask an administrator to assign BIFROST Whse - Full ori, or preview without lines.'));
        Parts.AddBusinessCentralError(Errors, 'invalid quantities, posting setup or source-document state');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Simulates receiving the Warehouse Receipt and rolls the transaction back; no persistent records are changed.', 'BIFROST Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'Use it to commit the receipt posting after reviewing the preview.'));
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
    begin
        exit(false);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only posting preview for a Warehouse Receipt. It captures predicted ledger entries and rolls back the transaction.';
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
        GLSetup: Record "General Ledger Setup";
        TempDocumentEntry: Record "Document Entry" temporary;
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler";
        PostingPreviewHelper: Codeunit "Posting Preview Helper ori";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        TotalsJson: JsonObject;
        PredictedJson: JsonObject;
        SourceArray: JsonArray;
        PreviewArray: JsonArray;
        PlannedLines: JsonArray;
        LCYCode: Code[10];
        EntryCount: Integer;
        GLEntryCount: Integer;
        Balanced: Boolean;
        Summary: Text;
        PreviewErrorText: Text;
        PreviewFieldNames: List of [Text];
        NoLinesToPostErr: Label 'Warehouse Receipt %1 has no lines to post.', Comment = '%1 = Whse. Receipt No., is-IS=Vöruhúsamóttaka %1 hefur engar línur til bókunar.';
        PreviewFailedErr: Label 'Posting preview failed and no entries were captured. The warehouse receipt cannot be posted in its current state.', Comment = 'is-IS=Bókunarforsýning mistókst og engar færslur voru teknar. Vöruhúsamóttakan getur ekki verið bókuð í núverandi stöðu.';
        NothingToPostNextStepTok: Label 'No receipt line has Qty. to Receive. Set quantities on the receipt lines.', Comment = 'is-IS=Engin móttökulína hefur Magn til móttöku. Setjið magn á móttökulínurnar.';
        OmitCommitPreviewErr: Label 'Posting preview cannot run inside a rollback chain (Omit Commit). Run this message type with Omit Commit set to false.', Comment = 'is-IS=Ekki er hægt að forskoða bókun innan afturköllunarkeðju (Omit Commit). Keyrðu þessa skilaboðategund með Omit Commit stillt á false.';
        OmitCommitPreviewNextStepTok: Label 'Call Dispatcher.Execute with OmitCommit = false, or use the HTTP/MCP API.', Comment = 'is-IS=Kallaðu á Dispatcher.Execute með OmitCommit = false eða notaðu HTTP/MCP API.';
        NothingPreviewedLbl: Label 'Nothing was previewed.', Comment = 'is-IS=Ekkert var forskoðað.';
        LinesDeniedLbl: Label 'You do not have permission to set quantities on warehouse receipt lines.', Comment = 'is-IS=Þú hefur ekki heimild til að setja magn á línur vöruhúsamóttöku.';
        LinesDeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori, or preview without lines.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori eða forskoðaðu án lína.';
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if Argument."Omit Commit" then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, OmitCommitPreviewErr, '', '', '', OmitCommitPreviewNextStepTok);
            exit;
        end;
        if not WhseRecordLookup.TryReadIdentifiers(Argument, 'systemId=guid,recordSystemId=guid,id=guid,receiptNo=no,no=no', RequestJson) then
            exit;
        // An unknown key is answered together with the lookup and line problems, so it does not hide them.
        RefuseUnknownKeys(RequestJson, Argument);

        if not FindWhseReceiptHeader(Argument, WhseReceiptHeader) then
            exit;

        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        if WhseReceiptLine.IsEmpty() then begin
            if Argument.HasCollectedErrors() then begin
                Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, NothingPreviewedLbl);
                exit;
            end;
            Argument.RespondWithError("Bifrost Error Code ori"::NothingToPreview, StrSubstNo(NoLinesToPostErr, WhseReceiptHeader."No."), '', '', '', NothingToPostNextStepTok);
            exit;
        end;
        DocLineQty.ReadLines(RequestJson, Argument, false, WhseReceiptHeader."No.", PlannedLines);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, NothingPreviewedLbl);
            exit;
        end;
        if PlannedLines.Count() > 0 then
            if not WhseReceiptLine.WritePermission() then begin
                Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, LinesDeniedLbl, 'lines', '', '', LinesDeniedNextStepLbl);
                exit;
            end;
        WhseReceiptLine.FindFirst();

        GLSetup.Get();
        LCYCode := GLSetup."LCY Code";

        if not PreviewWhseReceipt(WhseReceiptLine, PlannedLines, PostingPreviewEventHandler, PreviewErrorText) then begin
            if PreviewErrorText = '' then
                PreviewErrorText := PreviewFailedErr;
            PostingPreviewHelper.RespondWithPreviewError(Argument, PreviewErrorText, NothingToPostNextStepTok);
            exit;
        end;

        PostingPreviewHelper.GetPreviewFieldNames(PreviewFieldNames);

        PostingPreviewEventHandler.FillDocumentEntry(TempDocumentEntry);
        if TempDocumentEntry.FindSet() then
            repeat
                PostingPreviewHelper.AddTableToPreview(PreviewArray, PostingPreviewEventHandler, TempDocumentEntry."Table ID", TempDocumentEntry."Table Name", PreviewFieldNames);
            until TempDocumentEntry.Next() = 0;

        if not PostingPreviewHelper.EvaluatePreviewOutcome(Argument, PreviewArray, PostingPreviewEventHandler, NothingToPostNextStepTok, TotalsJson, Balanced, EntryCount, GLEntryCount) then

            exit;

        BuildSourceDocuments(WhseReceiptHeader."No.", SourceArray);
        BuildPredictedNumbers(PredictedJson, PostingPreviewEventHandler);
        Summary := BuildSummary(WhseReceiptHeader."No.", WhseReceiptHeader."Location Code", PreviewArray, PostingPreviewHelper.GLStatusSentence(GLEntryCount, Balanced));

        ResponseJson.Add('status', 'Success');
        PostingPreviewHelper.AddEntryCounts(ResponseJson, EntryCount, GLEntryCount);
        ResponseJson.Add('rollback', true);
        ResponseJson.Add('summary', Summary);
        ResponseJson.Add('receiptNo', WhseReceiptHeader."No.");
        ResponseJson.Add('locationCode', WhseReceiptHeader."Location Code");
        ResponseJson.Add('sourceDocuments', SourceArray);
        ResponseJson.Add('lcyCode', LCYCode);
        ResponseJson.Add('predictedNumbers', PredictedJson);
        ResponseJson.Add('totals', TotalsJson);
        ResponseJson.Add('preview', PreviewArray);

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

    local procedure BuildSourceDocuments(WhseReceiptNo: Code[20]; var SourceArray: JsonArray)
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        DocJson: JsonObject;
        SeenKeys: List of [Text];
        DedupKey: Text;
    begin
        WhseReceiptLine.SetRange("No.", WhseReceiptNo);
        WhseReceiptLine.SetLoadFields("Source Document", "Source No.");
        if WhseReceiptLine.FindSet() then
            repeat
                DedupKey := Format(WhseReceiptLine."Source Document") + '|' + WhseReceiptLine."Source No.";
                if not SeenKeys.Contains(DedupKey) then begin
                    SeenKeys.Add(DedupKey);
                    Clear(DocJson);
                    DocJson.Add('sourceDocument', Format(WhseReceiptLine."Source Document"));
                    DocJson.Add('sourceNo', WhseReceiptLine."Source No.");
                    SourceArray.Add(DocJson);
                end;
            until WhseReceiptLine.Next() = 0;
    end;

    /// <summary>
    /// Builds predicted posted document numbers by walking captured Item Ledger Entries and
    /// the captured Posted Whse. Receipt Header entry (if present). Each captured entry's
    /// Document No. is the number BC assigned during the rolled-back post.
    /// </summary>
    local procedure BuildPredictedNumbers(var PredictedJson: JsonObject; var PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler")
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        TempItemRecRef: RecordRef;
        TempPostedRecRef: RecordRef;
        PostedWhseReceiptNo: Code[20];
        PurchaseReceiptNo: Code[20];
        ReturnReceiptNo: Code[20];
        TransferReceiptNo: Code[20];
    begin
        Clear(PostedWhseReceiptNo);
        Clear(PurchaseReceiptNo);
        Clear(ReturnReceiptNo);
        Clear(TransferReceiptNo);

        // Posted Whse. Receipt No.
        TempPostedRecRef.Open(Database::"Posted Whse. Receipt Header", true);
        PostingPreviewEventHandler.GetEntries(Database::"Posted Whse. Receipt Header", TempPostedRecRef);
        if TempPostedRecRef.FindFirst() then begin
            TempPostedRecRef.SetTable(PostedWhseReceiptHeader);
            PostedWhseReceiptNo := PostedWhseReceiptHeader."No.";
        end;
        TempPostedRecRef.Close();

        // Posted source document numbers — walk Item Ledger Entry by Entry Type.
        // Receipt posting always produces positive-qty entries (goods coming in):
        //   Purchase + positive  ? Posted Purchase Receipt
        //   Sale + positive      ? Posted Return Receipt (customer returning goods to us)
        //   Transfer + positive  ? Posted Transfer Receipt (inbound side)
        TempItemRecRef.Open(Database::"Item Ledger Entry", true);
        PostingPreviewEventHandler.GetEntries(Database::"Item Ledger Entry", TempItemRecRef);
        if TempItemRecRef.FindSet() then
            repeat
                TempItemRecRef.SetTable(ItemLedgerEntry);
                if ItemLedgerEntry.Quantity > 0 then
                    case ItemLedgerEntry."Entry Type" of
                        ItemLedgerEntry."Entry Type"::Purchase:
                            if PurchaseReceiptNo = '' then
                                PurchaseReceiptNo := ItemLedgerEntry."Document No.";
                        ItemLedgerEntry."Entry Type"::Sale:
                            if ReturnReceiptNo = '' then
                                ReturnReceiptNo := ItemLedgerEntry."Document No.";
                        ItemLedgerEntry."Entry Type"::Transfer:
                            if TransferReceiptNo = '' then
                                TransferReceiptNo := ItemLedgerEntry."Document No.";
                    end;
            until TempItemRecRef.Next() = 0;
        TempItemRecRef.Close();

        PredictedJson.Add('postedWhseReceiptNo', PostedWhseReceiptNo);
        if PurchaseReceiptNo <> '' then
            PredictedJson.Add('postedPurchaseReceiptNo', PurchaseReceiptNo);
        if ReturnReceiptNo <> '' then
            PredictedJson.Add('postedReturnReceiptNo', ReturnReceiptNo);
        if TransferReceiptNo <> '' then
            PredictedJson.Add('postedTransferReceiptNo', TransferReceiptNo);
    end;

    local procedure BuildSummary(ReceiptNo: Code[20]; LocationCode: Code[10]; var PreviewArray: JsonArray; GLStatusText: Text): Text
    var
        PostingPreviewHelper: Codeunit "Posting Preview Helper ori";
        Summary: Text;
        SummaryLbl: Label 'Warehouse Receipt %1 at %2 preview produced %3 entries. %4', Comment = '%1 = receipt no., %2 = location code, %3 = entry count, %4 = G/L status sentence, is-IS=Forsýning bókunar vöruhúsamóttöku %1 á %2 myndaði %3 færslur. %4';
    begin
        Summary := StrSubstNo(SummaryLbl, ReceiptNo, LocationCode, PostingPreviewHelper.CountPreviewEntries(PreviewArray), GLStatusText);
        exit(Summary);
    end;

    /// <summary>
    /// Runs the BC built-in posting preview for a warehouse receipt and returns the
    /// Posting Preview Event Handler containing the captured (rolled-back) ledger entries.
    /// Binds `Whse.-Post Receipt (Yes/No)` (which has `EventSubscriberInstance = Manual`) so
    /// its `OnRunPreview` subscriber redirects the post into the preview engine. The
    /// Yes/No wrapper does not show a confirmation dialog under preview because the worker
    /// codeunit is never invoked — preview captures and rolls back before that point.
    /// </summary>
    local procedure PreviewWhseReceipt(var WhseReceiptLine: Record "Warehouse Receipt Line"; PlannedLines: JsonArray; var PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler"; var ErrorText: Text): Boolean
    var
        GenJnlPostPreview: Codeunit "Gen. Jnl.-Post Preview";
        WhsePostReceiptYesNo: Codeunit "Whse.-Post Receipt (Yes/No)";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
    begin
        // The per-line quantities are applied inside the preview run (Whse.-Post Receipt OnBeforeRun),
        // so Business Central rolls them back with the preview.
        Context.Reset();
        if PlannedLines.Count() > 0 then begin
            Payload.Add('documentNo', WhseReceiptLine."No.");
            Payload.Add('isShipment', false);
            Payload.Add('lines', PlannedLines);
            Context.SetPayload(Payload);
            BindSubscription(DocLineQty);
        end;
        BindSubscription(WhsePostReceiptYesNo);
        GenJnlPostPreview.SetContext(WhsePostReceiptYesNo, WhseReceiptLine);
        if GenJnlPostPreview.Run() then; // expected to throw Error('') after capturing entries
        UnbindSubscription(WhsePostReceiptYesNo);
        if PlannedLines.Count() > 0 then
            UnbindSubscription(DocLineQty);
        Context.Reset();

        if not GenJnlPostPreview.IsSuccess() then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;

        GenJnlPostPreview.GetPreviewHandler(PostingPreviewEventHandler);
        exit(true);
    end;
}
