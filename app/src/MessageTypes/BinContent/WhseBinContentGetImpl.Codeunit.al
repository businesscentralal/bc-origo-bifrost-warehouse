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
    var
        DescriptionLbl: Label 'Reads Bin Content rows with item, location, bin and variant filters.', Comment = 'is-IS=Les birgðainnihald hólfa með síum á vöru, staðsetningu, hólf og afbrigði.';
    begin
        exit(DescriptionLbl);
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
        Parameters.Add(ContractMgt.Parameter('tableView', 'string', false, 'Optional Business Central table view, for example WHERE(Quantity=FILTER(>0)). An unknown field returns InvalidFilterField. Write dates as YYYY-MM-DD and decimals with a dot.'));
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
        Parts: Codeunit "Whse Contract Parts ori";
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidFilterField, 'A table-view filter names a field that cannot be filtered.', 'Use a valid Bin Content field name.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, 'A table-view filter value cannot be read. The paging values have their own entry below.', 'Send text filter values.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::MultipleErrors, 'Both skip and take failed validation.', 'Correct every listed value and send the request again.'));
        Parts.AddCollectedPagingErrors(Errors);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Get', 'You want the bin itself (zone, ranking, blocking), not the stock in it.'));
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Read where an item is stored at a location',
            '{"itemNo":"1896-S","locationCode":"SILVER"}',
            '{"status":"Success","noOfRecords":1,"skip":0,"take":100,"result":[{"locationCode":"SILVER","binCode":"S-01-0001","itemNo":"1896-S","variantCode":"","unitOfMeasureCode":"PCS","quantity":10,"dedicated":false,"fixed":true,"zoneCode":"PICK","binTypeCode":"PICK"}]}'));
        Examples.Add(ContractMgt.Example(
            'Read bin content that holds stock, using a table view',
            '{"locationCode":"SILVER","tableView":"WHERE(Quantity=FILTER(>0))","take":50}',
            '{"status":"Success","noOfRecords":0,"skip":0,"take":50,"result":[]}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only, paged access to Bin Content with optional item, location, bin and variant filters.';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'One row is one item, variant and unit of measure in one bin; the same item in two bins is two rows. quantity is calculated from the warehouse entries when the row is read, so it is the stock now, in the unit of measure of the row. ' +
            'Rows with quantity 0 are returned too, for instance fixed bins that are empty; filter with a table view such as WHERE(Quantity=FILTER(>0)) to see only stock. ' +
            'itemNo, locationCode, binCode and variantCode are exact filters and are combined with each other and with tableView. An empty variantCode filter matches only content without a variant. ' +
            'No match is Success with noOfRecords 0 and an empty result, not an error. Only rows the caller may read are counted and returned. ' +
            'Rows are paged with skip and take; noOfRecords is the total before paging. ' +
            'Quantities that are reserved for or already assigned to open pick lines are not subtracted; read Warehouse.Activity.Get for open picks. ' +
            'To read the bin itself (description, zone, ranking, blocking) use Warehouse.Bin.Get.';
        exit(true);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Reads matching Bin Content records and returns a paged JSON result.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        BinContent: Record "Bin Content";
        Context: Codeunit "Whse Write Context ori";
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
        PagingProblemsLbl: Label 'The warehouse query contains invalid paging values.', Comment = 'is-IS=Fyrirspurn vöruhúss inniheldur ógild síðuskiptingargildi.';
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();

        RequestJson := Argument.GetRequestJson();
        if not Context.RespondOrReadPaging(RequestJson, Argument, PagingProblemsLbl, Skip, Take) then
            exit;

        RecRef.Open(Database::"Bin Content");
        RecRef.ReadIsolation := IsolationLevel::ReadCommitted;
        if RequestJson.Contains('tableView') then
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