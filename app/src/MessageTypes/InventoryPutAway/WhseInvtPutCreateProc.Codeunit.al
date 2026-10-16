namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;

/// <summary>
/// Creates inventory put-aways inside Codeunit.Run.
/// Report 7323 commits each created put-away, so a later failure does not roll it back.
/// </summary>
codeunit 10078421 "Whse InvtPut Create Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse InvtPut Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The inventory put-away create payload was empty.', Comment = 'is-IS=Gögnin til að stofna birgðafrágang voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        CreatePutaways(Payload, Result);
        Context.SetResult(Result);
    end;

    local procedure CreatePutaways(Payload: JsonObject; var Result: JsonObject)
    var
        WarehouseRequest: Record "Warehouse Request";
        CreateReport: Report "Create Invt Put-away/Pick/Mvmt";
        SourceDocument: Enum "Warehouse Request Source Document";
        SourceNo: Code[20];
        Putaways: JsonArray;
        NothingErr: Label 'No inventory put-away was created.', Comment = 'is-IS=Enginn birgðafrágangur var stofnaður.';
    begin
        SourceDocument := ParseSourceDocument(TextValue(Payload, 'sourceDocument'));
        SourceNo := CopyStr(TextValue(Payload, 'sourceNo'), 1, MaxStrLen(SourceNo));
        WarehouseRequest.SetRange("Source Document", SourceDocument);
        WarehouseRequest.SetRange("Source No.", SourceNo);
        WarehouseRequest.SetRange(Type, WarehouseRequest.Type::Inbound);
        CreateReport.UseRequestPage(false);
        CreateReport.InitializeRequest(true, false, false, false, true);
        CreateReport.SuppressMessages(true);
        CreateReport.SetTableView(WarehouseRequest);
        CreateReport.RunModal();
        BuildPutaways(SourceDocument, SourceNo, Putaways);
        if Putaways.Count() = 0 then
            Error(NothingErr);
        Result.Add('sourceDocument', TextValue(Payload, 'sourceDocument'));
        Result.Add('sourceNo', SourceNo);
        Result.Add('putaways', Putaways);
    end;

    local procedure BuildPutaways(SourceDocument: Enum "Warehouse Request Source Document"; SourceNo: Code[20]; var Putaways: JsonArray)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        PutawayJson: JsonObject;
    begin
        Clear(Putaways);
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Put-away");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", SourceNo);
        if not ActivityHeader.FindSet() then
            exit;
        repeat
            Clear(PutawayJson);
            WritePutaway(ActivityHeader, PutawayJson);
            Putaways.Add(PutawayJson);
        until ActivityHeader.Next() = 0;
    end;

    local procedure WritePutaway(ActivityHeader: Record "Warehouse Activity Header"; var PutawayJson: JsonObject)
    var
        Lines: JsonArray;
    begin
        BuildLines(ActivityHeader, Lines);
        PutawayJson.Add('putawayNo', ActivityHeader."No.");
        PutawayJson.Add('putawaySystemId', Format(ActivityHeader.SystemId, 0, 4));
        PutawayJson.Add('locationCode', ActivityHeader."Location Code");
        PutawayJson.Add('lineCount', Lines.Count());
        PutawayJson.Add('lines', Lines);
    end;

    local procedure BuildLines(ActivityHeader: Record "Warehouse Activity Header"; var Lines: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        LineJson: JsonObject;
    begin
        Clear(Lines);
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if not ActivityLine.FindSet() then
            exit;
        repeat
            Clear(LineJson);
            LineJson.Add('lineNo', ActivityLine."Line No.");
            LineJson.Add('itemNo', ActivityLine."Item No.");
            LineJson.Add('binCode', ActivityLine."Bin Code");
            LineJson.Add('quantity', ActivityLine.Quantity);
            LineJson.Add('qtyToHandle', ActivityLine."Qty. to Handle");
            LineJson.Add('qtyOutstanding', ActivityLine."Qty. Outstanding");
            Lines.Add(LineJson);
        until ActivityLine.Next() = 0;
    end;

    local procedure ParseSourceDocument(SourceText: Text) SourceDocument: Enum "Warehouse Request Source Document"
    var
        UnsupportedErr: Label 'Source document %1 is not supported.', Comment = '%1 = source document, is-IS=Upprunaskjal %1 er ekki stutt.';
    begin
        case UpperCase(DelChr(SourceText, '=', ' ')) of
            'PURCHASEORDER':
                exit(SourceDocument::"Purchase Order");
            'SALESRETURNORDER':
                exit(SourceDocument::"Sales Return Order");
            'INBOUNDTRANSFER':
                exit(SourceDocument::"Inbound Transfer");
        end;
        Error(UnsupportedErr, SourceText);
    end;

    local procedure ToActivitySource(SourceDocument: Enum "Warehouse Request Source Document") ActivitySource: Enum "Warehouse Activity Source Document"
    begin
        case SourceDocument of
            SourceDocument::"Purchase Order":
                exit(ActivitySource::"Purchase Order");
            SourceDocument::"Sales Return Order":
                exit(ActivitySource::"Sales Return Order");
            SourceDocument::"Inbound Transfer":
                exit(ActivitySource::"Inbound Transfer");
        end;
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;
}
