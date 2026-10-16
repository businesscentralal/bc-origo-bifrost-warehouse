namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.History;
using Microsoft.Sales.History;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;

/// <summary>
/// Posts an inventory pick inside Codeunit.Run.
/// Codeunit 7324 commits the post, so the help marks this type irreversible.
/// </summary>
codeunit 10078482 "Whse InvtPick Post Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse InvtPick Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The inventory pick post payload was empty.', Comment = 'is-IS=Gögnin til að bóka birgðatínslu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        PostPick(Payload, Result);
        Context.SetResult(Result);
    end;

    local procedure PostPick(Payload: JsonObject; var Result: JsonObject)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        WhseActivityPost: Codeunit "Whse.-Activity-Post";
        PickNo: Code[20];
        Invoice: Boolean;
        NothingToPostErr: Label 'There is no quantity to post.', Comment = 'is-IS=Ekkert magn er til að bóka.';
    begin
        PickNo := CopyStr(TextValue(Payload, 'pickNo'), 1, MaxStrLen(PickNo));
        Invoice := BooleanValue(Payload, 'invoice');
        ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", PickNo);
        ApplyQuantities(ActivityHeader, Payload);
        if not FindLineToPost(ActivityHeader, ActivityLine) then
            Error(NothingToPostErr);
        WhseActivityPost.ShowHideDialog(true);
        WhseActivityPost.SetInvoiceSourceDoc(Invoice);
        WhseActivityPost.Run(ActivityLine);
        WritePosted(ActivityHeader, Invoice, Result);
    end;

    local procedure FindLineToPost(ActivityHeader: Record "Warehouse Activity Header"; var ActivityLine: Record "Warehouse Activity Line"): Boolean
    begin
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if not ActivityLine.FindSet() then
            exit(false);
        repeat
            if ActivityLine."Qty. to Handle" <> 0 then
                exit(true);
        until ActivityLine.Next() = 0;
        exit(false);
    end;

    local procedure ApplyQuantities(ActivityHeader: Record "Warehouse Activity Header"; Payload: JsonObject)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Token: JsonToken;
        Lines: JsonArray;
        LineObject: JsonObject;
        LineNo: Integer;
        Quantity: Decimal;
    begin
        if not Payload.Get('lines', Token) then
            exit;
        if not Token.IsArray() then
            exit;
        Lines := Token.AsArray();
        foreach Token in Lines do begin
            LineObject := Token.AsObject();
            LineNo := IntegerValue(LineObject, 'lineNo');
            Quantity := DecimalValue(LineObject, 'qtyToHandle');
            ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo);
            ActivityLine.Validate("Qty. to Handle", Quantity);
            ActivityLine.Modify(true);
        end;
    end;

    local procedure WritePosted(ActivityHeader: Record "Warehouse Activity Header"; Invoice: Boolean; var Result: JsonObject)
    var
        PostedHeader: Record "Posted Invt. Pick Header";
        Lines: JsonArray;
        PostedQuantity: Decimal;
        PostedDocumentNo: Code[20];
        PostedInvoiceNo: Code[20];
        MissingPostedErr: Label 'The inventory pick was posted but the posted pick was not found.', Comment = 'is-IS=Birgðatínslan var bókuð en bókaða tínslan fannst ekki.';
    begin
        PostedHeader.SetRange("Invt Pick No.", ActivityHeader."No.");
        if not PostedHeader.FindLast() then
            Error(MissingPostedErr);
        PostedDocumentNo := FindPostedDocumentNo(ActivityHeader);
        if Invoice then
            PostedInvoiceNo := FindPostedInvoiceNo(ActivityHeader);
        PostedQuantity := BuildPostedLines(PostedHeader, Lines);
        Result.Add('pickNo', ActivityHeader."No.");
        Result.Add('postedPickNo', PostedHeader."No.");
        Result.Add('sourceDocument', Format(ActivityHeader."Source Document"));
        Result.Add('sourceNo', ActivityHeader."Source No.");
        Result.Add('postedDocumentNo', PostedDocumentNo);
        Result.Add('postedInvoiceNo', PostedInvoiceNo);
        Result.Add('invoice', Invoice);
        Result.Add('postedQuantity', PostedQuantity);
        Result.Add('lines', Lines);
    end;

    local procedure BuildPostedLines(PostedHeader: Record "Posted Invt. Pick Header"; var Lines: JsonArray): Decimal
    var
        PostedLine: Record "Posted Invt. Pick Line";
        LineJson: JsonObject;
        PostedQuantity: Decimal;
    begin
        Clear(Lines);
        PostedLine.SetRange("No.", PostedHeader."No.");
        if not PostedLine.FindSet() then
            exit(0);
        repeat
            Clear(LineJson);
            LineJson.Add('lineNo', PostedLine."Line No.");
            LineJson.Add('itemNo', PostedLine."Item No.");
            LineJson.Add('binCode', PostedLine."Bin Code");
            LineJson.Add('quantity', PostedLine.Quantity);
            Lines.Add(LineJson);
            PostedQuantity += PostedLine.Quantity;
        until PostedLine.Next() = 0;
        exit(PostedQuantity);
    end;

    local procedure FindPostedDocumentNo(ActivityHeader: Record "Warehouse Activity Header"): Code[20]
    var
        SalesShipmentHeader: Record "Sales Shipment Header";
        ReturnShipmentHeader: Record "Return Shipment Header";
        TransferShipmentHeader: Record "Transfer Shipment Header";
    begin
        case ActivityHeader."Source Document" of
            ActivityHeader."Source Document"::"Sales Order":
                begin
                    SalesShipmentHeader.SetRange("Order No.", ActivityHeader."Source No.");
                    if SalesShipmentHeader.FindLast() then
                        exit(SalesShipmentHeader."No.");
                end;
            ActivityHeader."Source Document"::"Purchase Return Order":
                begin
                    ReturnShipmentHeader.SetRange("Return Order No.", ActivityHeader."Source No.");
                    if ReturnShipmentHeader.FindLast() then
                        exit(ReturnShipmentHeader."No.");
                end;
            ActivityHeader."Source Document"::"Outbound Transfer":
                begin
                    TransferShipmentHeader.SetRange("Transfer Order No.", ActivityHeader."Source No.");
                    if TransferShipmentHeader.FindLast() then
                        exit(TransferShipmentHeader."No.");
                end;
        end;
        exit('');
    end;

    local procedure FindPostedInvoiceNo(ActivityHeader: Record "Warehouse Activity Header"): Code[20]
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        if ActivityHeader."Source Document" <> ActivityHeader."Source Document"::"Sales Order" then
            exit('');
        SalesInvoiceHeader.SetRange("Order No.", ActivityHeader."Source No.");
        if SalesInvoiceHeader.FindLast() then
            exit(SalesInvoiceHeader."No.");
        exit('');
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

    local procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;
}
