namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Markdown help for Warehouse.Activity.Get.
/// </summary>
codeunit 10078391 "Whse Activity Get Help ori"
{
    Access = Internal;

    /// <summary>Builds the request and response documentation.</summary>
    /// <returns>The message type help in Markdown.</returns>
    internal procedure GetHelpText(): Text
    var
        HelpBuilder: TextBuilder;
    begin
        HelpBuilder.AppendLine('# Warehouse.Activity.Get - Help');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Overview');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('Returns open warehouse activity headers, optionally including their lines. Registered warehouse activities and history are not included.');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('**Direction**: Outbound (read-only)  **Content-Type**: `text/json`');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Request Parameters');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('| Parameter | Type | Required | Notes |');
        HelpBuilder.AppendLine('|---|---|---|---|');
        HelpBuilder.AppendLine('| `activityType` | string | No | Exact warehouse activity type: `Put-away`, `Pick`, or `Movement`. |');
        HelpBuilder.AppendLine('| `no` | string | No | Warehouse activity number; returns an error if no open activity matches. |');
        HelpBuilder.AppendLine('| `systemId` | string | No | Activity SystemId GUID; returns an error if no open activity matches. |');
        HelpBuilder.AppendLine('| `whseDocumentNo` | string | No | Matches activities with at least one line for this warehouse document. |');
        HelpBuilder.AppendLine('| `locationCode` | string | No | Exact location code filter. |');
        HelpBuilder.AppendLine('| `assignedUserId` | string | No | Exact assigned user ID filter. |');
        HelpBuilder.AppendLine('| `includeLines` | boolean | No | Include line details; defaults to `false`. |');
        HelpBuilder.AppendLine('| `skip` | integer | No | Number of matching headers to skip; defaults to 0. |');
        HelpBuilder.AppendLine('| `take` | integer | No | Page size; defaults to 100 and is capped at 1000. |');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('## Request Example');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('```json');
        HelpBuilder.AppendLine('{');
        HelpBuilder.AppendLine('  "activityType": "Pick",');
        HelpBuilder.AppendLine('  "whseDocumentNo": "WHSHIP-0004",');
        HelpBuilder.AppendLine('  "locationCode": "WHITE",');
        HelpBuilder.AppendLine('  "assignedUserId": "",');
        HelpBuilder.AppendLine('  "includeLines": true,');
        HelpBuilder.AppendLine('  "skip": 0,');
        HelpBuilder.AppendLine('  "take": 20');
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
        HelpBuilder.AppendLine('  "take": 20,');
        HelpBuilder.AppendLine('  "result": [');
        HelpBuilder.AppendLine('    {');
        HelpBuilder.AppendLine('      "no": "PICK-000123",');
        HelpBuilder.AppendLine('      "systemId": "5b1a0000-0000-0000-0000-000000000000",');
        HelpBuilder.AppendLine('      "activityType": "Pick",');
        HelpBuilder.AppendLine('      "locationCode": "WHITE",');
        HelpBuilder.AppendLine('      "assignedUserId": "",');
        HelpBuilder.AppendLine('      "sortingMethod": "None",');
        HelpBuilder.AppendLine('      "lines": [');
        HelpBuilder.AppendLine('        {');
        HelpBuilder.AppendLine('          "lineNo": 10000,');
        HelpBuilder.AppendLine('          "itemNo": "1000",');
        HelpBuilder.AppendLine('          "binCode": "B-01-01",');
        HelpBuilder.AppendLine('          "zoneCode": "BULK",');
        HelpBuilder.AppendLine('          "unitOfMeasureCode": "PCS",');
        HelpBuilder.AppendLine('          "qtyToHandle": 5,');
        HelpBuilder.AppendLine('          "qtyHandled": 0,');
        HelpBuilder.AppendLine('          "qtyOutstanding": 5,');
        HelpBuilder.AppendLine('          "actionType": "Take",');
        HelpBuilder.AppendLine('          "whseDocumentType": "Shipment",');
        HelpBuilder.AppendLine('          "whseDocumentNo": "WHSHIP-0004",');
        HelpBuilder.AppendLine('          "whseDocumentLineNo": 10000');
        HelpBuilder.AppendLine('        }');
        HelpBuilder.AppendLine('      ]');
        HelpBuilder.AppendLine('    }');
        HelpBuilder.AppendLine('  ]');
        HelpBuilder.AppendLine('}');
        HelpBuilder.AppendLine('```');
        HelpBuilder.AppendLine('');
        HelpBuilder.AppendLine('`noOfRecords` counts matching open headers before paging. When a supplied `no` or `systemId` does not match, the response is a structured `Error` with code `RecordNotFound`.');
        exit(HelpBuilder.ToText());
    end;
}