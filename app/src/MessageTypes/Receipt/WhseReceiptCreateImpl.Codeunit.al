namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Receipt.Create message type.
/// Creates one Warehouse Receipt per source document supplied (Sales Return Order, Purchase Order,
/// or Inbound Transfer Order) by delegating to BC's Get Source Doc. Inbound (codeunit 5751).
/// Each source produces its own Warehouse Receipt Header (BC standard behaviour). Optional
/// `assignedUserId` and `postingDate` are applied to each created header after creation.
/// </summary>

using Microsoft.Inventory.Location;
using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;

using Origo.Bifrost;

codeunit 10078409 "Whse Receipt Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
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
        exit(Database::"Warehouse Receipt Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Creates Warehouse Receipt(s) from one or more released source documents (Sales Return Order, Purchase Order, Inbound Transfer Order).');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'warehouse receipt, create receipt, expect goods, prepare to receive, inbound receipt, goods arriving', Comment = 'is-IS=vöruhúsamóttaka, stofna móttöku, von á vörum, undirbúa móttöku, innmóttaka, vörur á leiðinni';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Creates inbound warehouse receipts from released sales return, purchase, or transfer orders; use Warehouse.Receipt.Post to receive one.', Comment = 'is-IS=Stofnar innleiðarmóttökur úr útgefnum söluskila-, innkaupa- eða millifærslupöntunum; notaðu Warehouse.Receipt.Post til að móttaka.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('data only');
        Envelope := Parts.RecordEnvelope(Forms, 'The request must contain one or more source documents under data.', true);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('data.sourceDocuments[].documentNo', 'document no.', 'The released Sales Return Order, Purchase Order or inbound Transfer Order from which a Warehouse Receipt is created.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('sourceDocuments', 'array', true, 'One or more source documents. Each child has sourceType (SalesReturnOrder, PurchaseOrder or TransferOrder) and documentNo.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Optional source-location check. It does not override the source document.'));
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'User assigned to each created Warehouse Receipt Header.'));
        Parameters.Add(ContractMgt.Parameter('postingDate', 'string', false, 'Posting date applied to each created Warehouse Receipt Header.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('noOfReceipts', 'integer', 'Number of Warehouse Receipts created.'));
        Fields.Add(ContractMgt.ResponseField('receipts', 'array', 'Created Warehouse Receipt summaries with recordSystemId, no, locationCode, assignedUserId, sourceType, sourceDocumentNo and linesCreated.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddSourceDocumentErrors(Errors, 'SalesReturnOrder, PurchaseOrder, TransferOrder');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Creates Warehouse Receipt Header and Line records and applies requested header fields.', 'BIFROST Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'Use it after creation to receive the Warehouse Receipt.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Create', 'Use it after posting when the received goods require put-away.'));
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
        Overview := 'Creates one Warehouse Receipt for each released Sales Return Order, Purchase Order or inbound Transfer Order supplied in sourceDocuments.';
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
        Dispatcher: Codeunit "Dispatcher ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        SourceToken: JsonToken;
        SourcesArray: JsonArray;
        ResultArray: JsonArray;
        LocationFilter: Code[10];
        AssignedUserIdValue: Code[50];
        PostingDateValue: Date;
        HasAssignedUserId: Boolean;
        HasPostingDate: Boolean;
        I: Integer;
        MissingSourcesErr: Label 'sourceDocuments is required and must contain at least one entry.', Locked = true;
        FieldWriteRestrictedErr: Label 'Field %1 is restricted for write on table %2.', Comment = '%1 = field caption, %2 = table caption', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        RequestJson := Argument.GetRequestJson();

        if not RequestJson.Get('sourceDocuments', SourceToken) then begin
            Argument.RespondWithError(MissingSourcesErr);
            exit;
        end;
        SourcesArray := SourceToken.AsArray();
        if SourcesArray.Count() = 0 then begin
            Argument.RespondWithError(MissingSourcesErr);
            exit;
        end;

        // Optional locationCode — used only to validate sources match (no override on the header).
        LocationFilter := ReadCode10(RequestJson, 'locationCode');
        if LocationFilter <> '' then
            if Dispatcher.IsFieldWriteRestricted(Database::"Warehouse Receipt Header", WhseReceiptHeader.FieldNo("Location Code")) then begin
                Argument.RespondWithError(StrSubstNo(FieldWriteRestrictedErr, WhseReceiptHeader.FieldCaption("Location Code"), WhseReceiptHeader.TableCaption()));
                exit;
            end;

        // Optional header overrides
        AssignedUserIdValue := ReadCode50(RequestJson, 'assignedUserId');
        HasAssignedUserId := AssignedUserIdValue <> '';
        if not Dispatcher.TryReadDate(Argument, RequestJson, 'postingDate', false, PostingDateValue) then
            exit;
        HasPostingDate := PostingDateValue <> 0D;

        // Process each source
        for I := 0 to SourcesArray.Count() - 1 do
            if not ProcessSource(Argument, SourcesArray, I, LocationFilter, AssignedUserIdValue, HasAssignedUserId, PostingDateValue, HasPostingDate, ResultArray) then
                exit;

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('noOfReceipts', ResultArray.Count());
        ResponseJson.Add('receipts', ResultArray);

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ProcessSource(var Argument: Record "Message Argument ori"; SourcesArray: JsonArray; Index: Integer; LocationFilter: Code[10]; AssignedUserIdValue: Code[50]; HasAssignedUserId: Boolean; PostingDateValue: Date; HasPostingDate: Boolean; var ResultArray: JsonArray): Boolean
    var
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        SourceToken: JsonToken;
        SourceObject: JsonObject;
        SourceType: Text;
        DocumentNo: Code[20];
        CreatedHeaderNo: Code[20];
        ReceiptJson: JsonObject;
        InvalidSourceErr: Label 'Source #%1 is missing sourceType or documentNo (both required).', Comment = '%1 = source index', Locked = true;
        UnsupportedSourceErr: Label 'Unsupported sourceType ''%1''. Expected: SalesReturnOrder, PurchaseOrder, TransferOrder.', Comment = '%1 = sourceType value', Locked = true;
        NoReceiptCreatedErr: Label 'No Warehouse Receipt was created for %1 ''%2'' — already on an open receipt, no lines remain to receive, or put-away already started.', Comment = '%1 = sourceType, %2 = documentNo', Locked = true;
    begin
        SourcesArray.Get(Index, SourceToken);
        SourceObject := SourceToken.AsObject();
        SourceType := ReadString(SourceObject, 'sourceType');
        DocumentNo := ReadCode20Direct(SourceObject, 'documentNo');
        if (SourceType = '') or (DocumentNo = '') then begin
            Argument.RespondWithError(StrSubstNo(InvalidSourceErr, Index + 1));
            exit(false);
        end;

        case UpperCase(SourceType) of
            'SALESRETURNORDER':
                if not CreateFromSalesReturnOrder(Argument, DocumentNo, LocationFilter, CreatedHeaderNo) then
                    exit(false);
            'PURCHASEORDER':
                if not CreateFromPurchaseOrder(Argument, DocumentNo, LocationFilter, CreatedHeaderNo) then
                    exit(false);
            'TRANSFERORDER':
                if not CreateFromTransferOrder(Argument, DocumentNo, LocationFilter, CreatedHeaderNo) then
                    exit(false);
            else begin
                Argument.RespondWithError(StrSubstNo(UnsupportedSourceErr, SourceType));
                exit(false);
            end;
        end;

        if CreatedHeaderNo = '' then begin
            Argument.RespondWithError(StrSubstNo(NoReceiptCreatedErr, SourceType, DocumentNo));
            exit(false);
        end;

        WhseReceiptHeader.Get(CreatedHeaderNo);
        if HasAssignedUserId then begin
            WhseReceiptHeader.Validate("Assigned User ID", AssignedUserIdValue);
            WhseReceiptHeader.Modify(true);
        end;
        if HasPostingDate then begin
            WhseReceiptHeader.Validate("Posting Date", PostingDateValue);
            WhseReceiptHeader.Modify(true);
        end;

        ReceiptJson.Add('recordSystemId', Format(WhseReceiptHeader.SystemId, 0, 4));
        ReceiptJson.Add('no', WhseReceiptHeader."No.");
        ReceiptJson.Add('locationCode', WhseReceiptHeader."Location Code");
        ReceiptJson.Add('assignedUserId', WhseReceiptHeader."Assigned User ID");
        ReceiptJson.Add('sourceType', SourceType);
        ReceiptJson.Add('sourceDocumentNo', DocumentNo);
        ReceiptJson.Add('linesCreated', CountLines(WhseReceiptHeader."No."));
        ResultArray.Add(ReceiptJson);
        exit(true);
    end;

    local procedure CreateFromSalesReturnOrder(var Argument: Record "Message Argument ori"; DocumentNo: Code[20]; LocationFilter: Code[10]; var CreatedHeaderNo: Code[20]): Boolean
    var
        SalesHeader: Record "Sales Header";
        Location: Record Location;
        GetSourceDocInbound: Codeunit "Get Source Doc. Inbound";
        SalesNotReleasedErr: Label 'Sales Return Order ''%1'' is not Released. Release it before creating a Warehouse Receipt.', Comment = '%1 = sales return order no.', Locked = true;
        LocationMismatchErr: Label 'Sales Return Order ''%1'' uses location ''%2'' which does not match the requested locationCode ''%3''.', Comment = '%1 = sales return order no., %2 = source location, %3 = requested location', Locked = true;
        LocationNotRequireReceiveErr: Label 'Location ''%1'' (from Sales Return Order ''%2'') does not require receipt routing — set ''Require Receive'' on the Location card to enable warehouse receipts.', Comment = '%1 = location code, %2 = sales return order no.', Locked = true;
    begin
        if not SalesHeader.Get(SalesHeader."Document Type"::"Return Order", DocumentNo) then begin
            Argument.RespondWithRecordNotFound(Database::"Sales Header", DocumentNo, 'sourceDocuments.documentNo');
            exit(false);
        end;
        if SalesHeader.Status <> SalesHeader.Status::Released then begin
            Argument.RespondWithError(StrSubstNo(SalesNotReleasedErr, DocumentNo));
            exit(false);
        end;
        if (LocationFilter <> '') and (LocationFilter <> SalesHeader."Location Code") then begin
            Argument.RespondWithError(StrSubstNo(LocationMismatchErr, DocumentNo, SalesHeader."Location Code", LocationFilter));
            exit(false);
        end;
        if SalesHeader."Location Code" <> '' then begin
            Location.Get(SalesHeader."Location Code");
            if not Location."Require Receive" then begin
                Argument.RespondWithError(StrSubstNo(LocationNotRequireReceiveErr, Location.Code, DocumentNo));
                exit(false);
            end;
        end;

        GetSourceDocInbound.CreateFromSalesReturnOrderHideDialog(SalesHeader);
        CreatedHeaderNo := FindHeaderForSource(Database::"Sales Line", SalesHeader."Document Type".AsInteger(), DocumentNo);
        exit(true);
    end;

    local procedure CreateFromPurchaseOrder(var Argument: Record "Message Argument ori"; DocumentNo: Code[20]; LocationFilter: Code[10]; var CreatedHeaderNo: Code[20]): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        Location: Record Location;
        GetSourceDocInbound: Codeunit "Get Source Doc. Inbound";
        PurchNotReleasedErr: Label 'Purchase Order ''%1'' is not Released. Release it before creating a Warehouse Receipt.', Comment = '%1 = purchase order no.', Locked = true;
        LocationMismatchErr: Label 'Purchase Order ''%1'' uses location ''%2'' which does not match the requested locationCode ''%3''.', Comment = '%1 = purchase order no., %2 = source location, %3 = requested location', Locked = true;
        LocationNotRequireReceiveErr: Label 'Location ''%1'' (from Purchase Order ''%2'') does not require receipt routing — set ''Require Receive'' on the Location card to enable warehouse receipts.', Comment = '%1 = location code, %2 = purchase order no.', Locked = true;
    begin
        if not PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocumentNo) then begin
            Argument.RespondWithRecordNotFound(Database::"Purchase Header", DocumentNo, 'sourceDocuments.documentNo');
            exit(false);
        end;
        if PurchaseHeader.Status <> PurchaseHeader.Status::Released then begin
            Argument.RespondWithError(StrSubstNo(PurchNotReleasedErr, DocumentNo));
            exit(false);
        end;
        if (LocationFilter <> '') and (LocationFilter <> PurchaseHeader."Location Code") then begin
            Argument.RespondWithError(StrSubstNo(LocationMismatchErr, DocumentNo, PurchaseHeader."Location Code", LocationFilter));
            exit(false);
        end;
        if PurchaseHeader."Location Code" <> '' then begin
            Location.Get(PurchaseHeader."Location Code");
            if not Location."Require Receive" then begin
                Argument.RespondWithError(StrSubstNo(LocationNotRequireReceiveErr, Location.Code, DocumentNo));
                exit(false);
            end;
        end;

        GetSourceDocInbound.CreateFromPurchOrderHideDialog(PurchaseHeader);
        CreatedHeaderNo := FindHeaderForSource(Database::"Purchase Line", PurchaseHeader."Document Type".AsInteger(), DocumentNo);
        exit(true);
    end;

    local procedure CreateFromTransferOrder(var Argument: Record "Message Argument ori"; DocumentNo: Code[20]; LocationFilter: Code[10]; var CreatedHeaderNo: Code[20]): Boolean
    var
        TransferHeader: Record "Transfer Header";
        Location: Record Location;
        GetSourceDocInbound: Codeunit "Get Source Doc. Inbound";
        TransferNotReleasedErr: Label 'Transfer Order ''%1'' is not Released. Release it before creating a Warehouse Receipt.', Comment = '%1 = transfer order no.', Locked = true;
        LocationMismatchErr: Label 'Transfer Order ''%1'' receives at ''%2'' which does not match the requested locationCode ''%3''.', Comment = '%1 = transfer order no., %2 = transfer-to location, %3 = requested location', Locked = true;
        LocationNotRequireReceiveErr: Label 'Location ''%1'' (Transfer-to on Transfer Order ''%2'') does not require receipt routing — set ''Require Receive'' on the Location card to enable warehouse receipts.', Comment = '%1 = location code, %2 = transfer order no.', Locked = true;
    begin
        if not TransferHeader.Get(DocumentNo) then begin
            Argument.RespondWithRecordNotFound(Database::"Transfer Header", DocumentNo, 'sourceDocuments.documentNo');
            exit(false);
        end;
        if TransferHeader.Status <> TransferHeader.Status::Released then begin
            Argument.RespondWithError(StrSubstNo(TransferNotReleasedErr, DocumentNo));
            exit(false);
        end;
        if (LocationFilter <> '') and (LocationFilter <> TransferHeader."Transfer-to Code") then begin
            Argument.RespondWithError(StrSubstNo(LocationMismatchErr, DocumentNo, TransferHeader."Transfer-to Code", LocationFilter));
            exit(false);
        end;
        if TransferHeader."Transfer-to Code" <> '' then begin
            Location.Get(TransferHeader."Transfer-to Code");
            if not Location."Require Receive" then begin
                Argument.RespondWithError(StrSubstNo(LocationNotRequireReceiveErr, Location.Code, DocumentNo));
                exit(false);
            end;
        end;

        GetSourceDocInbound.CreateFromInbndTransferOrderHideDialog(TransferHeader);
        CreatedHeaderNo := FindHeaderForSource(Database::"Transfer Line", 1, DocumentNo);
        exit(true);
    end;

    /// <summary>
    /// Locates the Warehouse Receipt Header by inspecting Warehouse Receipt Line rows for the
    /// supplied source. For Sales / Purchase lines the subtype filter pins to the right document
    /// type (Sales Return Order vs Sales Order, Purchase Order vs Purchase Return Order).
    /// For Transfer Line, subtype 1 (Inbound) is used to disambiguate from outbound transfers.
    /// </summary>
    local procedure FindHeaderForSource(SourceTableNo: Integer; SourceSubtype: Integer; SourceDocumentNo: Code[20]): Code[20]
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
    begin
        WhseReceiptLine.SetRange("Source Type", SourceTableNo);
        if SourceTableNo in [Database::"Sales Line", Database::"Purchase Line", Database::"Transfer Line"] then
            WhseReceiptLine.SetRange("Source Subtype", SourceSubtype);
        WhseReceiptLine.SetRange("Source No.", SourceDocumentNo);
        if not WhseReceiptLine.FindLast() then
            exit('');
        exit(WhseReceiptLine."No.");
    end;

    local procedure CountLines(HeaderNo: Code[20]): Integer
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
    begin
        WhseReceiptLine.SetRange("No.", HeaderNo);
        exit(WhseReceiptLine.Count());
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

    local procedure ReadCode10(JObject: JsonObject; PropertyName: Text): Code[10]
    begin
        exit(CopyStr(UpperCase(ReadString(JObject, PropertyName)), 1, 10));
    end;

    local procedure ReadCode50(JObject: JsonObject; PropertyName: Text): Code[50]
    begin
        exit(CopyStr(UpperCase(ReadString(JObject, PropertyName)), 1, 50));
    end;

    local procedure ReadCode20Direct(JObject: JsonObject; PropertyName: Text): Code[20]
    begin
        exit(CopyStr(ReadString(JObject, PropertyName), 1, 20));
    end;
}
