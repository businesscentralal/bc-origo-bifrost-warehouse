namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Markdown help for Warehouse.BinContent.Get.
/// </summary>
codeunit 10036939 "Whse BinContent Get Help ori"
{
    Access = Internal;

    /// <summary>Builds the request and response documentation.</summary>
    /// <returns>The message type help in Markdown.</returns>
    internal procedure GetHelpText(): Text
    var
        HelpBuilder: TextBuilder;
    begin
        HelpBuilder.AppendLine('# Warehouse.BinContent.Get - Help');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Overview');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('Returns Bin Content rows for an item, location, bin and variant. This is a read-only list operation; no matching rows is a successful empty result.');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('**Direction**: Outbound (read-only)  **Content-Type**: `text/json`');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Request Parameters');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('| Parameter | Type | Required | Notes |');
        HelpBuilder.AppendLine('|---|---|---|---|');
        HelpBuilder.AppendLine('| `itemNo` | string | No | Exact item number filter. |');
        HelpBuilder.AppendLine('| `locationCode` | string | No | Exact location code filter. |');
        HelpBuilder.AppendLine('| `binCode` | string | No | Exact bin code filter. |');
        HelpBuilder.AppendLine('| `variantCode` | string | No | Exact variant code filter; an empty string selects the blank variant. |');
        HelpBuilder.AppendLine('| `tableView` | string | No | Standard Business Central table-view filter. |');
        HelpBuilder.AppendLine('| `skip` | integer | No | Number of matching rows to skip; defaults to 0. |');
        HelpBuilder.AppendLine('| `take` | integer | No | Page size; defaults to 100 and is capped at 1000. |');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Request Example');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('```json');
        HelpBuilder.AppendLine('{');
        HelpBuilder.AppendLine('  "itemNo": "1000",');
        HelpBuilder.AppendLine('  "locationCode": "WHITE",');
        HelpBuilder.AppendLine('  "binCode": "B-01-01",');
        HelpBuilder.AppendLine('  "variantCode": "",');
        HelpBuilder.AppendLine('  "tableView": "",');
        HelpBuilder.AppendLine('  "skip": 0,');
        HelpBuilder.AppendLine('  "take": 50');
        HelpBuilder.AppendLine('}');
        HelpBuilder.AppendLine('```');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Response Example');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('```json');
        HelpBuilder.AppendLine('{');
        HelpBuilder.AppendLine('  "status": "Success",');
        HelpBuilder.AppendLine('  "noOfRecords": 1,');
        HelpBuilder.AppendLine('  "skip": 0,');
        HelpBuilder.AppendLine('  "take": 50,');
        HelpBuilder.AppendLine('  "result": [');
        HelpBuilder.AppendLine('    {');
        HelpBuilder.AppendLine('      "locationCode": "WHITE",');
        HelpBuilder.AppendLine('      "binCode": "B-01-01",');
        HelpBuilder.AppendLine('      "itemNo": "1000",');
        HelpBuilder.AppendLine('      "variantCode": "",');
        HelpBuilder.AppendLine('      "unitOfMeasureCode": "PCS",');
        HelpBuilder.AppendLine('      "quantity": 25,');
        HelpBuilder.AppendLine('      "dedicated": false,');
        HelpBuilder.AppendLine('      "fixed": true,');
        HelpBuilder.AppendLine('      "zoneCode": "BULK",');
        HelpBuilder.AppendLine('      "binTypeCode": "PICK"');
        HelpBuilder.AppendLine('    }');
        HelpBuilder.AppendLine('  ]');
        HelpBuilder.AppendLine('}');
        HelpBuilder.AppendLine('```');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('`noOfRecords` is the unpaged match count. `skip` and `take` apply to the returned rows.');
        exit(HelpBuilder.ToText());
    end;
}