namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.BinContent.Get as a filtered, paged read of Bin Content.
/// </summary>
codeunit 10078388 "Whse BinContent Get Impl ori" implements "Msg Interface ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read Bin Content.</summary>
    /// <returns>True when the caller has read permission on Bin Content.</returns>
    procedure IsEnabled(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(GetFilterTableNo());
        exit(RecRef.ReadPermission());
    end;

    /// <summary>Returns the table used to evaluate caller read permission.</summary>
    /// <returns>The Bin Content table ID.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Bin Content");
    end;

    /// <summary>Returns a short description of Warehouse.BinContent.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    begin
        exit('Reads Bin Content rows with item, location, bin and variant filters.');
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Returns the request and response help for this message type.</summary>
    /// <param name="Argument">The message argument receiving the help.</param>
    procedure GetMessageHelpAsMarkdownDocument(var Argument: Record "Message Argument ori")
    var
        HelpCodeunit: Codeunit "Whse BinContent Get Help ori";
    begin
        Argument.SetResponseMarkdown(HelpCodeunit.GetHelpText());
    end;

    /// <summary>Reads matching Bin Content records and returns a paged JSON result.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        BinContent: Record "Bin Content";
        RecRef: RecordRef;
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        ResultJson: JsonObject;
        Skip: Integer;
        Take: Integer;
        NoOfRecords: Integer;
        ItemNo: Text;
        LocationCode: Text;
        BinCode: Text;
        VariantCode: Text;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();

        RequestJson := Argument.GetRequestJson();
        Argument.EvaluateSkipTake(RequestJson, Skip, Take);

        RecRef.Open(Database::"Bin Content");
        RecRef.ReadIsolation := IsolationLevel::ReadCommitted;
        if not Argument.ApplyTableView(RequestJson, RecRef) then begin
            RecRef.Close();
            exit;
        end;
        RecRef.SetTable(BinContent);
        RecRef.Close();

        BinContent.ReadIsolation := IsolationLevel::ReadCommitted;
        BinContent.SetLoadFields(
            "Location Code", "Bin Code", "Item No.", "Variant Code", "Unit of Measure Code",
            Quantity, Dedicated, Fixed, "Zone Code", "Bin Type Code");
        BinContent.SetAutoCalcFields(Quantity);
        BinContent.SetPermissionFilter();

        if TryGetRequestText(RequestJson, 'itemNo', ItemNo) then
            BinContent.SetRange("Item No.", CopyStr(ItemNo, 1, MaxStrLen(BinContent."Item No.")));
        if TryGetRequestText(RequestJson, 'locationCode', LocationCode) then
            BinContent.SetRange("Location Code", CopyStr(LocationCode, 1, MaxStrLen(BinContent."Location Code")));
        if TryGetRequestText(RequestJson, 'binCode', BinCode) then
            BinContent.SetRange("Bin Code", CopyStr(BinCode, 1, MaxStrLen(BinContent."Bin Code")));
        if TryGetRequestText(RequestJson, 'variantCode', VariantCode) then
            BinContent.SetRange("Variant Code", CopyStr(VariantCode, 1, MaxStrLen(BinContent."Variant Code")));

        NoOfRecords := BinContent.Count();
        if Skip < NoOfRecords then
            if BinContent.FindSet() then begin
                if Skip > 0 then
                    BinContent.Next(Skip);

                repeat
                    Clear(ResultJson);
                    ResultJson.Add('locationCode', BinContent."Location Code");
                    ResultJson.Add('binCode', BinContent."Bin Code");
                    ResultJson.Add('itemNo', BinContent."Item No.");
                    ResultJson.Add('variantCode', BinContent."Variant Code");
                    ResultJson.Add('unitOfMeasureCode', BinContent."Unit of Measure Code");
                    ResultJson.Add('quantity', BinContent.Quantity);
                    ResultJson.Add('dedicated', BinContent.Dedicated);
                    ResultJson.Add('fixed', BinContent.Fixed);
                    ResultJson.Add('zoneCode', BinContent."Zone Code");
                    ResultJson.Add('binTypeCode', BinContent."Bin Type Code");
                    ResultArray.Add(ResultJson);

                    if ResultArray.Count() >= Take then
                        break;
                until BinContent.Next() = 0;
            end;

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('noOfRecords', NoOfRecords);
        ResponseJson.Add('skip', Skip);
        ResponseJson.Add('take', Take);
        ResponseJson.Add('result', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure TryGetRequestText(RequestJson: JsonObject; PropertyName: Text; var Value: Text): Boolean
    var
        Token: JsonToken;
    begin
        Clear(Value);
        if not RequestJson.Get(PropertyName, Token) then
            exit(false);
        if not Token.IsValue() or Token.AsValue().IsNull() then
            exit(false);
        Value := Token.AsValue().AsText();
        exit(true);
    end;
}