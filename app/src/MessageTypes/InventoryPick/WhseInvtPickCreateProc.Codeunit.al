namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;

/// <summary>
/// Creates inventory picks inside Codeunit.Run.
/// Report 7323 commits each created pick, so a later failure does not roll it back.
/// </summary>
codeunit 10078480 "Whse InvtPick Create Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse InvtPick Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The inventory pick create payload was empty.', Comment = 'is-IS=Gögnin til að stofna birgðatínslu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        CreatePicks(Payload, Result);
        Context.SetResult(Result);
    end;

    local procedure CreatePicks(Payload: JsonObject; var Result: JsonObject)
    var
        WarehouseRequest: Record "Warehouse Request";
        CreateReport: Report "Create Invt Put-away/Pick/Mvmt";
        SourceDocument: Enum "Warehouse Request Source Document";
        SourceNo: Code[20];
        Picks: JsonArray;
        NothingErr: Label 'No inventory pick was created.', Comment = 'is-IS=Engin birgðatínsla var stofnuð.';
    begin
        SourceDocument := ParseSourceDocument(TextValue(Payload, 'sourceDocument'));
        SourceNo := CopyStr(TextValue(Payload, 'sourceNo'), 1, MaxStrLen(SourceNo));
        WarehouseRequest.SetRange("Source Document", SourceDocument);
        WarehouseRequest.SetRange("Source No.", SourceNo);
        WarehouseRequest.SetRange(Type, WarehouseRequest.Type::Outbound);
        CreateReport.UseRequestPage(false);
        CreateReport.InitializeRequest(false, true, false, false, true);
        CreateReport.SuppressMessages(true);
        CreateReport.SetTableView(WarehouseRequest);
        CreateReport.RunModal();
        // Report 7323 leaves Qty. to Handle at zero when the request page is suppressed.
        FillQtyToHandle(SourceDocument, SourceNo);
        BuildPicks(SourceDocument, SourceNo, Picks);
        if Picks.Count() = 0 then
            Error(NothingErr);
        Result.Add('sourceDocument', TextValue(Payload, 'sourceDocument'));
        Result.Add('sourceNo', SourceNo);
        Result.Add('picks', Picks);
    end;

    local procedure BuildPicks(SourceDocument: Enum "Warehouse Request Source Document"; SourceNo: Code[20]; var Picks: JsonArray)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        PickJson: JsonObject;
    begin
        Clear(Picks);
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Pick");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", SourceNo);
        if not ActivityHeader.FindSet() then
            exit;
        repeat
            Clear(PickJson);
            WritePick(ActivityHeader, PickJson);
            Picks.Add(PickJson);
        until ActivityHeader.Next() = 0;
    end;

    local procedure WritePick(ActivityHeader: Record "Warehouse Activity Header"; var PickJson: JsonObject)
    var
        Lines: JsonArray;
    begin
        BuildLines(ActivityHeader, Lines);
        PickJson.Add('pickNo', ActivityHeader."No.");
        PickJson.Add('pickSystemId', Format(ActivityHeader.SystemId, 0, 4));
        PickJson.Add('locationCode', ActivityHeader."Location Code");
        PickJson.Add('lineCount', Lines.Count());
        PickJson.Add('lines', Lines);
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

    local procedure FillQtyToHandle(SourceDocument: Enum "Warehouse Request Source Document"; SourceNo: Code[20])
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Pick");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", SourceNo);
        if not ActivityHeader.FindSet() then
            exit;
        repeat
            ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
            ActivityLine.SetRange("No.", ActivityHeader."No.");
            if ActivityLine.FindSet() then
                repeat
                    if (ActivityLine."Qty. to Handle" = 0) and (ActivityLine."Qty. Outstanding" > 0) then begin
                        // Assign without Validate. A tracked line without a lot rejects Validate,
                        // and a try function cannot write the quantity afterwards.
                        ActivityLine."Qty. to Handle" := ActivityLine."Qty. Outstanding";
                        ActivityLine."Qty. to Handle (Base)" := ActivityLine."Qty. Outstanding (Base)";
                        ActivityLine.Modify(true);
                    end;
                until ActivityLine.Next() = 0;
        until ActivityHeader.Next() = 0;
    end;

    local procedure ParseSourceDocument(SourceText: Text) SourceDocument: Enum "Warehouse Request Source Document"
    var
        UnsupportedErr: Label 'Source document %1 is not supported.', Comment = '%1 = source document, is-IS=Upprunaskjal %1 er ekki stutt.';
    begin
        case UpperCase(DelChr(SourceText, '=', ' ')) of
            'SALESORDER':
                exit(SourceDocument::"Sales Order");
            'PURCHASERETURNORDER':
                exit(SourceDocument::"Purchase Return Order");
            'OUTBOUNDTRANSFER':
                exit(SourceDocument::"Outbound Transfer");
            'ASSEMBLYCONSUMPTION':
                exit(SourceDocument::"Assembly Consumption");
            'PROD.CONSUMPTION', 'PRODCONSUMPTION', 'PRODUCTIONCONSUMPTION':
                exit(SourceDocument::"Prod. Consumption");
        end;
        Error(UnsupportedErr, SourceText);
    end;

    local procedure ToActivitySource(SourceDocument: Enum "Warehouse Request Source Document") ActivitySource: Enum "Warehouse Activity Source Document"
    begin
        case SourceDocument of
            SourceDocument::"Sales Order":
                exit(ActivitySource::"Sales Order");
            SourceDocument::"Purchase Return Order":
                exit(ActivitySource::"Purchase Return Order");
            SourceDocument::"Outbound Transfer":
                exit(ActivitySource::"Outbound Transfer");
            SourceDocument::"Assembly Consumption":
                exit(ActivitySource::"Assembly Consumption");
            SourceDocument::"Prod. Consumption":
                exit(ActivitySource::"Prod. Consumption");
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
