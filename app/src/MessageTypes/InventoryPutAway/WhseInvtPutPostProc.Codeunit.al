namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.History;
using Microsoft.Sales.History;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;

/// <summary>
/// Posts an inventory put-away inside Codeunit.Run.
/// Codeunit 7324 commits the post, so the help marks this type irreversible.
/// </summary>
codeunit 10078423 "Whse InvtPut Post Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse InvtPut Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The inventory put-away post payload was empty.', Comment = 'is-IS=Gögnin til að bóka birgðafrágang voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        PostPutaway(Payload, Result);
        Context.SetResult(Result);
    end;

    local procedure PostPutaway(Payload: JsonObject; var Result: JsonObject)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        WhseActivityPost: Codeunit "Whse.-Activity-Post";
        PickNo: Code[20];
        Invoice: Boolean;
        NothingToPostErr: Label 'There is no quantity to post.', Comment = 'is-IS=Ekkert magn er til að bóka.';
    begin
        PickNo := CopyStr(TextValue(Payload, 'putawayNo'), 1, MaxStrLen(PickNo));
        Invoice := BooleanValue(Payload, 'invoice');
        ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PickNo);
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
            ApplyBin(ActivityLine, LineObject);
            ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo);
            ActivityLine.Validate("Qty. to Handle", Quantity);
            ActivityLine.Modify(true);
        end;
    end;

    local procedure WritePosted(ActivityHeader: Record "Warehouse Activity Header"; Invoice: Boolean; var Result: JsonObject)
    var
        PostedHeader: Record "Posted Invt. Put-away Header";
        Lines: JsonArray;
        PostedQuantity: Decimal;
        PostedDocumentNo: Code[20];
        PostedInvoiceNo: Code[20];
        MissingPostedErr: Label 'The inventory put-away was posted but the posted put-away was not found.', Comment = 'is-IS=Birgðafrágangurinn var bókaður en bókfærði frágangurinn fannst ekki.';
    begin
        PostedHeader.SetRange("Invt. Put-away No.", ActivityHeader."No.");
        if not PostedHeader.FindLast() then
            Error(MissingPostedErr);
        PostedDocumentNo := FindPostedDocumentNo(ActivityHeader);
        if Invoice then
            PostedInvoiceNo := FindPostedInvoiceNo(ActivityHeader);
        PostedQuantity := BuildPostedLines(PostedHeader, Lines);
        Result.Add('putawayNo', ActivityHeader."No.");
        Result.Add('postedPutawayNo', PostedHeader."No.");
        Result.Add('sourceDocument', Format(ActivityHeader."Source Document"));
        Result.Add('sourceNo', ActivityHeader."Source No.");
        Result.Add('postedDocumentNo', PostedDocumentNo);
        Result.Add('postedInvoiceNo', PostedInvoiceNo);
        Result.Add('invoice', Invoice);
        Result.Add('postedQuantity', PostedQuantity);
        Result.Add('lines', Lines);
    end;

    local procedure BuildPostedLines(PostedHeader: Record "Posted Invt. Put-away Header"; var Lines: JsonArray): Decimal
    var
        PostedLine: Record "Posted Invt. Put-away Line";
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

    local procedure ApplyBin(ActivityLine: Record "Warehouse Activity Line"; LineObject: JsonObject)
    var
        BinCode: Code[20];
    begin
        BinCode := CopyStr(TextValue(LineObject, 'binCode'), 1, MaxStrLen(BinCode));
        if BinCode = '' then
            exit;
        if ActivityLine."Bin Code" = BinCode then
            exit;
        ActivityLine.Validate("Bin Code", BinCode);
        ActivityLine.Modify(true);
    end;

    local procedure FindPostedDocumentNo(ActivityHeader: Record "Warehouse Activity Header"): Code[20]
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ReturnReceiptHeader: Record "Return Receipt Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
    begin
        case ActivityHeader."Source Document" of
            ActivityHeader."Source Document"::"Purchase Order":
                begin
                    PurchRcptHeader.SetRange("Order No.", ActivityHeader."Source No.");
                    if PurchRcptHeader.FindLast() then
                        exit(PurchRcptHeader."No.");
                end;
            ActivityHeader."Source Document"::"Sales Return Order":
                begin
                    ReturnReceiptHeader.SetRange("Return Order No.", ActivityHeader."Source No.");
                    if ReturnReceiptHeader.FindLast() then
                        exit(ReturnReceiptHeader."No.");
                end;
            ActivityHeader."Source Document"::"Inbound Transfer":
                begin
                    TransferReceiptHeader.SetRange("Transfer Order No.", ActivityHeader."Source No.");
                    if TransferReceiptHeader.FindLast() then
                        exit(TransferReceiptHeader."No.");
                end;
        end;
        exit('');
    end;

    local procedure FindPostedInvoiceNo(ActivityHeader: Record "Warehouse Activity Header"): Code[20]
    var
        PurchInvHeader: Record "Purch. Inv. Header";
    begin
        if ActivityHeader."Source Document" <> ActivityHeader."Source Document"::"Purchase Order" then
            exit('');
        PurchInvHeader.SetRange("Order No.", ActivityHeader."Source No.");
        if PurchInvHeader.FindLast() then
            exit(PurchInvHeader."No.");
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
