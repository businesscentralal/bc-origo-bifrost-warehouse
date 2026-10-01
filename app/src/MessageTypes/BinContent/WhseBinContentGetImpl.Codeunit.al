namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.BinContent.Get as a filtered, paged read of Bin Content.
/// </summary>
codeunit 10078388 "Whse BinContent Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
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

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'bin content, bin quantity, item in bin, warehouse stock, stock by bin, inventory by location', Comment = 'is-IS=birgðainnihald hólfs, magn í hólfi, vara í hólfi, vöruhúsabirgðir, birgðir eftir hólfi, birgðir eftir staðsetningu';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Reads paged Bin Content; use Warehouse.Activity.Get for open warehouse picks and put-aways.', Comment = 'is-IS=Lesaðgangur. Les blaðsíðuskipt birgðainnihald hólfa; notaðu Warehouse.Activity.Get fyrir opnar tínslur og fráganga í vöruhúsi.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('filter only');
        Envelope := Parts.RecordEnvelope(Forms, 'No single record is required; filters under data select the Bin Content rows.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('data.itemNo, data.locationCode, data.binCode, data.variantCode', 'filter', 'Optional filters for the Bin Content collection.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddPagingParameters(Parameters);
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', false, 'Filter by item number.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Filter by location code.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Filter by bin code.'));
        Parameters.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Filter by item variant code.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        ResultFields: JsonArray;
        Result: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('noOfRecords', 'integer', 'Total number of matching Bin Content records before paging.'));
        Fields.Add(ContractMgt.ResponseField('skip', 'integer', 'Number of records skipped.'));
        Fields.Add(ContractMgt.ResponseField('take', 'integer', 'Maximum number of records requested.'));
        ResultFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        ResultFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin code.'));
        ResultFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        ResultFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        ResultFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure code.'));
        ResultFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Bin quantity.'));
        ResultFields.Add(ContractMgt.ResponseField('dedicated', 'boolean', 'Whether the content is dedicated.'));
        ResultFields.Add(ContractMgt.ResponseField('fixed', 'boolean', 'Whether the bin is fixed for the item.'));
        ResultFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone code.'));
        ResultFields.Add(ContractMgt.ResponseField('binTypeCode', 'string', 'Bin type code.'));
        Result.Add('name', 'result');
        Result.Add('type', 'array');
        Result.Add('description', 'The paged Bin Content rows.');
        Result.Add('children', ResultFields);
        Fields.Add(Result);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidFilterField, 'A table-view filter names a field that cannot be filtered.', 'Use a valid Bin Content field name.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, 'A paging or filter value cannot be read.', 'Send integer paging values and text filter values.'));
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads Bin Content and changes nothing.', 'BIFROST Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to read open warehouse picks and put-aways instead of Bin Content.'));
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    begin
        exit(false);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only, paged access to Bin Content with optional item, location, bin and variant filters.';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Clear(Notes);
        exit(false);
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
    begin
        Argument.SetResponseMarkdown('');
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