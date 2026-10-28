namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;

/// <summary>
/// Per-line quantities for Warehouse.Receipt.Post, Warehouse.Shipment.Post and their previews (#54).
/// Reads and validates the optional lines[] of a request, writes Qty. to Receive or Qty. to Ship through Validate,
/// and summarises posted and remaining quantity per line. Bound manually by the preview types: during a posting
/// preview it applies the quantities inside Business Central's preview run, so they are rolled back with it.
/// </summary>
codeunit 10078438 "Whse Doc Line Qty ori"
{
    Access = Internal;
    EventSubscriberInstance = Manual;

    /// <summary>Reads lines[] from the request and checks every line against the document.</summary>
    /// <param name="RequestJson">The request.</param>
    /// <param name="Argument">Collects the errors.</param>
    /// <param name="IsShipment">True for a warehouse shipment, false for a warehouse receipt.</param>
    /// <param name="DocumentNo">The warehouse receipt or shipment number.</param>
    /// <param name="PlannedLines">Receives one object per valid line: lineNo and quantity.</param>
    internal procedure ReadLines(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; IsShipment: Boolean; DocumentNo: Code[20]; var PlannedLines: JsonArray)
    var
        Token: JsonToken;
        Lines: JsonArray;
        Seen: List of [Integer];
        Index: Integer;
        FormatLbl: Label 'lines must be an array of line objects.', Comment = 'is-IS=lines verður að vera fylki línuhluta.';
        FormatNextStepLbl: Label 'Send lines as an array of objects with lineNo and the quantity.', Comment = 'is-IS=Sendu lines sem fylki hluta með lineNo og magni.';
    begin
        Clear(PlannedLines);
        if not RequestJson.Get('lines', Token) then
            exit;
        if Token.IsValue() then
            if Token.AsValue().IsNull() then
                exit;
        if not Token.IsArray() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'lines', '', 'array', FormatNextStepLbl);
            exit;
        end;
        Lines := Token.AsArray();
        for Index := 0 to Lines.Count() - 1 do begin
            Lines.Get(Index, Token);
            ReadOneLine(Token, Index, Argument, IsShipment, DocumentNo, Seen, PlannedLines);
        end;
    end;

    /// <summary>Returns whether at least one line would post a quantity.</summary>
    /// <param name="IsShipment">True for a warehouse shipment.</param>
    /// <param name="DocumentNo">The document number.</param>
    /// <param name="PlannedLines">The validated lines of the request.</param>
    /// <returns>True when a listed line has a quantity, or an unlisted line keeps one.</returns>
    internal procedure HasQuantityToPost(IsShipment: Boolean; DocumentNo: Code[20]; PlannedLines: JsonArray): Boolean
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ShipmentLine: Record "Warehouse Shipment Line";
        Planned: Dictionary of [Integer, Decimal];
        LineNo: Integer;
    begin
        ToDictionary(PlannedLines, Planned);
        foreach LineNo in Planned.Keys() do
            if Planned.Get(LineNo) <> 0 then
                exit(true);
        if IsShipment then begin
            ShipmentLine.SetLoadFields("No.", "Line No.", "Qty. to Ship");
            ShipmentLine.SetRange("No.", DocumentNo);
            ShipmentLine.SetFilter("Qty. to Ship", '<>0');
            if ShipmentLine.FindSet() then
                repeat
                    if not Planned.ContainsKey(ShipmentLine."Line No.") then
                        exit(true);
                until ShipmentLine.Next() = 0;
            exit(false);
        end;
        ReceiptLine.SetLoadFields("No.", "Line No.", "Qty. to Receive");
        ReceiptLine.SetRange("No.", DocumentNo);
        ReceiptLine.SetFilter("Qty. to Receive", '<>0');
        if ReceiptLine.FindSet() then
            repeat
                if not Planned.ContainsKey(ReceiptLine."Line No.") then
                    exit(true);
            until ReceiptLine.Next() = 0;
        exit(false);
    end;

    /// <summary>Summarises, per document line, the quantity the post will handle and the quantity left after it.</summary>
    /// <param name="IsShipment">True for a warehouse shipment.</param>
    /// <param name="DocumentNo">The document number.</param>
    /// <param name="PlannedLines">The validated lines of the request.</param>
    /// <returns>One object per line: lineNo, itemNo, quantityPosted and quantityRemaining.</returns>
    internal procedure LineSummary(IsShipment: Boolean; DocumentNo: Code[20]; PlannedLines: JsonArray) Summary: JsonArray
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ShipmentLine: Record "Warehouse Shipment Line";
        Planned: Dictionary of [Integer, Decimal];
        Quantity: Decimal;
    begin
        ToDictionary(PlannedLines, Planned);
        if IsShipment then begin
            ShipmentLine.SetLoadFields("No.", "Line No.", "Item No.", "Qty. to Ship", "Qty. Outstanding");
            ShipmentLine.SetRange("No.", DocumentNo);
            if ShipmentLine.FindSet() then
                repeat
                    Quantity := ShipmentLine."Qty. to Ship";
                    if Planned.ContainsKey(ShipmentLine."Line No.") then
                        Quantity := Planned.Get(ShipmentLine."Line No.");
                    Summary.Add(SummaryLine(ShipmentLine."Line No.", ShipmentLine."Item No.", Quantity, ShipmentLine."Qty. Outstanding" - Quantity));
                until ShipmentLine.Next() = 0;
            exit;
        end;
        ReceiptLine.SetLoadFields("No.", "Line No.", "Item No.", "Qty. to Receive", "Qty. Outstanding");
        ReceiptLine.SetRange("No.", DocumentNo);
        if ReceiptLine.FindSet() then
            repeat
                Quantity := ReceiptLine."Qty. to Receive";
                if Planned.ContainsKey(ReceiptLine."Line No.") then
                    Quantity := Planned.Get(ReceiptLine."Line No.");
                Summary.Add(SummaryLine(ReceiptLine."Line No.", ReceiptLine."Item No.", Quantity, ReceiptLine."Qty. Outstanding" - Quantity));
            until ReceiptLine.Next() = 0;
    end;

    /// <summary>Validates the planned quantities onto the document lines. Lines that are not listed keep their value.</summary>
    /// <param name="IsShipment">True for a warehouse shipment.</param>
    /// <param name="DocumentNo">The document number.</param>
    /// <param name="PlannedLines">The validated lines of the request.</param>
    internal procedure ApplyQuantities(IsShipment: Boolean; DocumentNo: Code[20]; PlannedLines: JsonArray)
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ShipmentLine: Record "Warehouse Shipment Line";
        Planned: Dictionary of [Integer, Decimal];
        LineNo: Integer;
    begin
        ToDictionary(PlannedLines, Planned);
        foreach LineNo in Planned.Keys() do
            if IsShipment then begin
                ShipmentLine.Get(DocumentNo, LineNo);
                if ShipmentLine."Qty. to Ship" <> Planned.Get(LineNo) then begin
                    ShipmentLine.Validate("Qty. to Ship", Planned.Get(LineNo));
                    ShipmentLine.Modify(true);
                end;
            end else begin
                ReceiptLine.Get(DocumentNo, LineNo);
                if ReceiptLine."Qty. to Receive" <> Planned.Get(LineNo) then begin
                    ReceiptLine.Validate("Qty. to Receive", Planned.Get(LineNo));
                    ReceiptLine.Modify(true);
                end;
            end;
    end;

    /// <summary>Applies the quantities stored in the write context. Used inside the posting preview run.</summary>
    internal procedure ApplyStoredQuantities()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        Token: JsonToken;
        DocumentNo: Code[20];
        IsShipment: Boolean;
    begin
        if not Context.TryGetPayload(Payload) then
            exit;
        if not Payload.Get('lines', Token) then
            exit;
        if not Token.IsArray() then
            exit;
        IsShipment := Context.IsTrue(Payload, 'isShipment');
        DocumentNo := CopyStr(TextOf(Payload, 'documentNo'), 1, MaxStrLen(DocumentNo));
        ApplyQuantities(IsShipment, DocumentNo, Token.AsArray());
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", 'OnBeforeRun', '', false, false)]
    local procedure ApplyReceiptQuantitiesInPreview(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; var SuppressCommit: Boolean; PreviewMode: Boolean)
    begin
        if PreviewMode then
            ApplyStoredQuantities();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Shipment", 'OnBeforeRun', '', false, false)]
    local procedure ApplyShipmentQuantitiesInPreview(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; var SuppressCommit: Boolean; PreviewMode: Boolean)
    begin
        if PreviewMode then
            ApplyStoredQuantities();
    end;

    local procedure ReadOneLine(Token: JsonToken; Index: Integer; var Argument: Record "Message Argument ori"; IsShipment: Boolean; DocumentNo: Code[20]; var Seen: List of [Integer]; var PlannedLines: JsonArray)
    var
        ReceiptLine: Record "Warehouse Receipt Line";
        ShipmentLine: Record "Warehouse Shipment Line";
        Location: Record Location;
        Context: Codeunit "Whse Write Context ori";
        LineObject: JsonObject;
        Planned: JsonObject;
        QtyKey: Text;
        LineNo: Integer;
        Quantity: Decimal;
        Outstanding: Decimal;
        LinePresent: Boolean;
        QuantityPresent: Boolean;
        LineFormatOk: Boolean;
        QuantityFormatOk: Boolean;
        FormatLbl: Label 'Each line must be an object.', Comment = 'is-IS=Hver lína verður að vera hlutur.';
        FormatNextStepLbl: Label 'Send lines as an array of objects with lineNo and the quantity.', Comment = 'is-IS=Sendu lines sem fylki hluta með lineNo og magni.';
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line position in the request, counted from 1, %2 = field, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send lineNo and the quantity on every line.', Comment = 'is-IS=Sendu lineNo og magnið á hverri línu.';
        DuplicateLbl: Label 'Line %1 is listed more than once.', Comment = '%1 = line no., is-IS=Lína %1 er talin oftar en einu sinni.';
        DuplicateNextStepLbl: Label 'Send each line once.', Comment = 'is-IS=Sendu hverja línu einu sinni.';
        NotFoundLbl: Label 'Line %1 is not on document %2.', Comment = '%1 = line no., %2 = document no., is-IS=Lína %1 er ekki á skjali %2.';
        NotFoundNextStepLbl: Label 'Read the lines first.', Comment = 'is-IS=Lestu línurnar fyrst.';
        RangeLbl: Label 'The quantity %1 on line %2 must be from zero up to the outstanding quantity %3.', Comment = '%1 = quantity, %2 = line no., %3 = outstanding quantity, is-IS=Magnið %1 á línu %2 verður að vera frá núlli upp í útistandandi magn %3.';
        RangeNextStepLbl: Label 'Read the outstanding quantity on the line and lower it.', Comment = 'is-IS=Lestu útistandandi magn á línunni og lækkaðu það.';
        PickLbl: Label 'The quantity %1 on line %2 is more than the picked quantity %3 that is not yet shipped.', Comment = '%1 = quantity, %2 = line no., %3 = picked and not shipped, is-IS=Magnið %1 á línu %2 er meira en tínt magn %3 sem hefur ekki enn verið afhent.';
        PickNextStepLbl: Label 'Register the pick first.', Comment = 'is-IS=Skráðu tínsluna fyrst.';
    begin
        if IsShipment then
            QtyKey := 'qtyToShip'
        else
            QtyKey := 'qtyToReceive';
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, LineParameter(Index, 'lineNo'), '', 'object', FormatNextStepLbl);
            exit;
        end;
        LineObject := Token.AsObject();
        RefuseUnknownLineKeys(LineObject, Index, QtyKey, Argument);
        LineFormatOk := Context.ReadInteger(LineObject, 'lineNo', Argument, LineNo, LinePresent, LineParameter(Index, 'lineNo'));
        QuantityFormatOk := Context.ReadDecimal(LineObject, QtyKey, Argument, Quantity, QuantityPresent, LineParameter(Index, QtyKey));
        // A value of the wrong type is already answered as InvalidParameterFormat; only an absent key is missing.
        if not LinePresent and LineFormatOk then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'lineNo'), LineParameter(Index, 'lineNo'), '', '', MissingNextStepLbl);
        if not QuantityPresent and QuantityFormatOk then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, QtyKey), LineParameter(Index, QtyKey), '', '', MissingNextStepLbl);
        if not LinePresent or not QuantityPresent then
            exit;
        if Seen.Contains(LineNo) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(DuplicateLbl, LineNo), LineParameter(Index, 'lineNo'), Format(LineNo), '', DuplicateNextStepLbl);
            exit;
        end;
        Seen.Add(LineNo);
        if IsShipment then begin
            ShipmentLine.SetLoadFields("No.", "Line No.", "Location Code", "Qty. Outstanding", "Qty. Picked", "Qty. Shipped");
            if not ShipmentLine.Get(DocumentNo, LineNo) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(NotFoundLbl, LineNo, DocumentNo), LineParameter(Index, 'lineNo'), Format(LineNo), '', NotFoundNextStepLbl);
                exit;
            end;
            Outstanding := ShipmentLine."Qty. Outstanding";
        end else begin
            ReceiptLine.SetLoadFields("No.", "Line No.", "Qty. Outstanding");
            if not ReceiptLine.Get(DocumentNo, LineNo) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(NotFoundLbl, LineNo, DocumentNo), LineParameter(Index, 'lineNo'), Format(LineNo), '', NotFoundNextStepLbl);
                exit;
            end;
            Outstanding := ReceiptLine."Qty. Outstanding";
        end;
        if (Quantity < 0) or (Quantity > Outstanding) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(RangeLbl, Format(Quantity, 0, 9), LineNo, Format(Outstanding, 0, 9)), LineParameter(Index, QtyKey), Format(Quantity, 0, 9), '', RangeNextStepLbl);
            exit;
        end;
        if IsShipment then
            if Location.RequirePicking(ShipmentLine."Location Code") then
                if Quantity > ShipmentLine."Qty. Picked" - ShipmentLine."Qty. Shipped" then begin
                    Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(PickLbl, Format(Quantity, 0, 9), LineNo, Format(ShipmentLine."Qty. Picked" - ShipmentLine."Qty. Shipped", 0, 9)), LineParameter(Index, QtyKey), Format(Quantity, 0, 9), '', PickNextStepLbl);
                    exit;
                end;
        Planned.Add('lineNo', LineNo);
        Planned.Add('quantity', Quantity);
        PlannedLines.Add(Planned);
    end;

    local procedure RefuseUnknownLineKeys(LineObject: JsonObject; Index: Integer; QtyKey: Text; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in LineObject.Keys() do
            if (KeyName <> 'lineNo') and (KeyName <> QtyKey) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), LineParameter(Index, KeyName), KeyName, '', UnknownNextStepLbl);
    end;

    local procedure SummaryLine(LineNo: Integer; ItemNo: Code[20]; Posted: Decimal; Remaining: Decimal) Line: JsonObject
    begin
        Line.Add('lineNo', LineNo);
        Line.Add('itemNo', ItemNo);
        Line.Add('quantityPosted', Posted);
        Line.Add('quantityRemaining', Remaining);
    end;

    local procedure ToDictionary(PlannedLines: JsonArray; var Planned: Dictionary of [Integer, Decimal])
    var
        Token: JsonToken;
        LineToken: JsonToken;
        QuantityToken: JsonToken;
    begin
        Clear(Planned);
        foreach Token in PlannedLines do begin
            Token.AsObject().Get('lineNo', LineToken);
            Token.AsObject().Get('quantity', QuantityToken);
            Planned.Set(LineToken.AsValue().AsInteger(), QuantityToken.AsValue().AsDecimal());
        end;
    end;

    local procedure TextOf(Parent: JsonObject; Name: Text): Text
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

    local procedure LineParameter(Index: Integer; KeyName: Text): Text
    var
        LineParameterLbl: Label 'lines[%1].%2', Locked = true;
    begin
        exit(StrSubstNo(LineParameterLbl, Index, KeyName));
    end;
}
