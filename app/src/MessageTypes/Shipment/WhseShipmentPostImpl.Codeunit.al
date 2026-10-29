namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Shipment.Post message type.
/// Posts a Warehouse Shipment using BC's Whse.-Post Shipment (codeunit 5763). Always gated by
/// `BIFROST WhsePost ori`. When `invoice = true`, also gated by `BIFROST WhseInv ori` because the
/// invoice pass writes to the G/L Register.
/// Optional lines[] set Qty. to Ship per line (#54); the quantities and the posting run in this
/// codeunit's own OnRun inside Codeunit.Run, so a failure leaves the quantities unchanged.
/// </summary>

using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Posting;

using Origo.Bifrost;

codeunit 10078407 "Whse Shipment Post Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        WhsePostShipment: Codeunit "Whse.-Post Shipment";
        Payload: JsonObject;
        Token: JsonToken;
        ShipmentNo: Code[20];
        MissingPayloadErr: Label 'The shipment posting payload was empty.', Comment = 'is-IS=Gögnin til að bóka afhendingu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Payload.Get('shipmentNo', Token);
        ShipmentNo := CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(ShipmentNo));
        Payload.Get('lines', Token);
        DocLineQty.ApplyQuantities(true, ShipmentNo, Token.AsArray());
        WhseShipmentLine.SetRange("No.", ShipmentNo);
        WhseShipmentLine.FindFirst();
        WhsePostShipment.SetPostingSettings(Context.IsTrue(Payload, 'invoice'));
        // The outer Codeunit.Run commits once, or the caller does under Omit Commit.
        WhsePostShipment.SetSuppressCommit(true);
        WhsePostShipment.Run(WhseShipmentLine);
    end;

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
    var
        DescriptionLbl: Label 'Posts a Warehouse Shipment (ship, optionally invoice), optionally with a quantity per line.', Comment = 'is-IS=Bókar vöruhúsaafhendingu (afhending, valfrjálst reikningur), valfrjálst með magni á hverja línu.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'post warehouse shipment, ship goods, goods left the warehouse, dispatch goods, send the goods out', Comment = 'is-IS=bóka vöruhúsaafhendingu, afhenda vörur, vörur farnar úr vöruhúsi, senda vörur út, senda vörur af stað';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Posts an existing Warehouse Shipment; use Warehouse.Shipment.PreviewPost to inspect the result first.', Comment = 'is-IS=Óafturkræft. Bókar fyrirliggjandi vöruhúsaafhendingu; notaðu Warehouse.Shipment.PreviewPost til að skoða niðurstöðuna fyrst.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Shipment to post: its SystemId or No.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the Warehouse Shipment Header.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the Warehouse Shipment Header.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.recordSystemId, data.id, data.shipmentNo, data.no', 'guid or document no.', 'The identifier keys accepted for the Warehouse Shipment Header. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        LineChildren: JsonArray;
        LinesParameter: JsonObject;
    begin
        Parameters.Add(ContractMgt.Parameter('invoice', 'boolean', false, 'Also invoice the shipped source documents. Defaults to false and requires BIFROST WhseInv ori when true.'));
        LineChildren.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Warehouse shipment line number. Each line may be listed once.'));
        LineChildren.Add(ContractMgt.Parameter('qtyToShip', 'number', true, 'Quantity to ship on that line, from zero up to the outstanding quantity, and at a location that requires pick up to the picked quantity not yet shipped.'));
        LinesParameter := ContractMgt.Parameter('lines', 'array', false, 'Optional per-line quantities to ship. Lines that are not listed keep their current Qty. to Ship.');
        LinesParameter.Add('children', LineChildren);
        Parameters.Add(LinesParameter);
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Warehouse shipment line number (inside lines).'));
        Parameters.Add(ContractMgt.Parameter('qtyToShip', 'number', true, 'Quantity to ship on that line, from zero up to the outstanding quantity, and at a location that requires pick up to the picked quantity not yet shipped (inside lines).'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('shipmentNo', 'string', 'The posted Warehouse Shipment source number.'));
        Fields.Add(ContractMgt.ResponseField('invoice', 'boolean', 'Whether the invoice pass was requested.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseShipmentNo', 'string', 'Posted Warehouse Shipment number when available.'));
        Fields.Add(ContractMgt.ResponseField('postedWhseShipmentSystemId', 'string', 'Posted Warehouse Shipment SystemId when available.'));
        Fields.Add(ContractMgt.ResponseField('postedDocuments', 'array', 'Distinct posted source-document summaries.'));
        Fields.Add(ContractMgt.ResponseField('lines', 'array', 'Per shipment line: lineNo, itemNo, quantityPosted and quantityRemaining on the shipment after the post.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddDocumentPostErrors(Errors, 'Warehouse Shipment Header', 'systemId, recordSystemId, id, shipmentNo, no', 'qtyToShip', true);
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Sets the listed quantities to ship and posts the Warehouse Shipment, optionally invoicing its source documents; Business Central commits the posting. The warehouse shipment is moved to history when it is fully shipped.', 'BIFROST WhsePost ori; BIFROST WhseInv ori when invoice is true');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.PreviewPost', 'Use it to inspect predicted entries without committing before posting.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it to register a pick before posting when a pick was created.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PostedDocument.Get', 'Use it to read the posted warehouse shipment.'));
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
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Ship 2 of 5 on line 10000 of shipment SH000001',
            '{"shipmentNo":"SH000001","lines":[{"lineNo":10000,"qtyToShip":2}]}',
            '{"status":"Success","shipmentNo":"SH000001","invoice":false,"postedWhseShipmentNo":"S_000001","postedWhseShipmentSystemId":"6f1c1d2e-0000-0000-0000-000000000007","postedDocuments":[{"postedSourceDocument":"Posted Shipment","postedSourceNo":"102001","sourceDocument":"Sales Order","sourceNo":"101005"}],"lines":[{"lineNo":10000,"itemNo":"1896-S","quantityPosted":2,"quantityRemaining":3}]}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Irreversibly posts a Warehouse Shipment, and Business Central commits the posting. Optional lines set Qty. to Ship per line first; lines that are not listed keep their value. Invoicing is optional and is a separate permission-gated pass.', Comment = 'is-IS=Bókar vöruhúsaafhendingu óafturkræft og Business Central staðfestir bókunina. Valfrjálsar línur setja fyrst magn til afhendingar á hverja línu; línur sem eru ekki taldar upp halda gildi sínu. Reikningsfærsla er valfrjáls og er sérstök umferð sem krefst heimildar.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Posting commits; under Omit Commit the caller''s transaction commits instead. The caller needs the BIFROST WhsePost ori permission set, and also BIFROST WhseInv ori when invoice is true; without the second one the whole call is refused and nothing is shipped. ' +
            'invoice defaults to false, so the source documents are shipped but not invoiced; with true the shipped source documents are invoiced in the same posting. It must be a JSON boolean. ' +
            'lines sets Qty. to Ship per listed line; lines that are not listed keep the quantity they have now, and that quantity counts when Business Central checks that something is left to post. Each lineNo may be listed once and the quantity must be from zero up to the outstanding quantity. ' +
            'At a location that requires pick the quantity cannot be above the picked quantity that is not yet shipped, so register the pick first with Warehouse.Pick.Register. ' +
            'The call is refused, with nothing posted, when the shipment has no lines or when every line would ship zero. Unknown keys, bad line values and the nothing-to-post case are answered together as MultipleErrors. ' +
            'The quantities are set in the same run as the posting, so a failure leaves them unchanged. A shipment that is only partly shipped stays open for the remaining quantity; a fully shipped one is moved to history. ' +
            'In the answer, quantityPosted is the quantity the post handles and quantityRemaining is the outstanding quantity less that, worked out before the post. postedWhseShipmentNo and postedWhseShipmentSystemId are left out if no Posted Whse. Shipment is found. ' +
            'Use Warehouse.Shipment.PreviewPost first to see the entries.';
        exit(true);
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        RequestValueReader: Codeunit "Request Value Reader ori";
        Context: Codeunit "Whse Write Context ori";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        Payload: JsonObject;
        PostedDocsArray: JsonArray;
        PlannedLines: JsonArray;
        LineSummary: JsonArray;
        Invoice: Boolean;
        NoLinesToPostErr: Label 'Warehouse Shipment %1 has no lines to post.', Comment = '%1 = Whse. Shipment No., is-IS=Vöruhúsaafhending %1 hefur engar línur til bókunar.';
        NothingLbl: Label 'Every line of warehouse shipment %1 would ship zero.', Comment = '%1 = shipment no., is-IS=Hver lína vöruhúsaafhendingar %1 myndi afhenda núll.';
        NothingNextStepLbl: Label 'Set a quantity above zero on at least one line.', Comment = 'is-IS=Settu magn yfir núlli á að minnsta kosti eina línu.';
        ProblemsLbl: Label 'Nothing was posted.', Comment = 'is-IS=Ekkert var bókað.';
    begin
        Context.Reset();
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;

        if not WhseRecordLookup.TryReadIdentifiers(Argument, 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', RequestJson) then
            exit;
        if not RequestValueReader.TryReadBoolean(Argument, RequestJson, 'invoice', false, Invoice) then
            exit;

        if Invoice then
            if not WhsePostingGate.AssertCanInvoice(Argument) then
                exit;

        // An unknown key is answered together with the lookup and line problems, so it does not hide them.
        RefuseUnknownKeys(RequestJson, Argument);

        if not FindWhseShipmentHeader(Argument, WhseShipmentHeader) then
            exit;

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if WhseShipmentLine.IsEmpty() then begin
            if Argument.HasCollectedErrors() then begin
                Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
                exit;
            end;
            Argument.RespondWithError(StrSubstNo(NoLinesToPostErr, WhseShipmentHeader."No."));
            exit;
        end;

        DocLineQty.ReadLines(RequestJson, Argument, true, WhseShipmentHeader."No.", PlannedLines);
        if not Argument.HasCollectedErrors() then
            if not DocLineQty.HasQuantityToPost(true, WhseShipmentHeader."No.", PlannedLines) then
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NothingLbl, WhseShipmentHeader."No."), 'lines', '', '', NothingNextStepLbl);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        LineSummary := DocLineQty.LineSummary(true, WhseShipmentHeader."No.", PlannedLines);

        Payload.Add('shipmentNo', WhseShipmentHeader."No.");
        Payload.Add('invoice', Invoice);
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Shipment Post Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Shipment Post Impl ori") then begin
                Context.Reset();
                Argument.RespondWithError(GetLastErrorText());
                exit;
            end;
        Context.Reset();

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('shipmentNo', WhseShipmentHeader."No.");
        ResponseJson.Add('invoice', Invoice);

        if FindPostedWhseShipment(WhseShipmentHeader."No.", PostedWhseShipmentHeader) then begin
            ResponseJson.Add('postedWhseShipmentNo', PostedWhseShipmentHeader."No.");
            ResponseJson.Add('postedWhseShipmentSystemId', Format(PostedWhseShipmentHeader.SystemId, 0, 4));
            AppendPostedSourceDocuments(PostedWhseShipmentHeader."No.", PostedDocsArray);
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
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['systemId', 'recordSystemId', 'id', 'shipmentNo', 'no', 'invoice', 'lines']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
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
