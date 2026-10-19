namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Shared worksheet logic for Warehouse.Worksheet.GetDocuments and Warehouse.Worksheet.CreateActivities (#55):
/// reads and resolves a pick or put-away worksheet and writes its lines as JSON.
/// </summary>
codeunit 10078468 "Whse Worksheet Helper ori"
{
    Access = Internal;

    /// <summary>Reads worksheetType, worksheetTemplateName, worksheetName and locationCode (or the subject) and collects format and missing errors.</summary>
    /// <param name="RequestJson">The request.</param>
    /// <param name="Argument">Collects the errors.</param>
    /// <param name="IsPick">Receives true for a pick worksheet, false for a put-away worksheet.</param>
    /// <param name="TemplateName">Receives the worksheet template name.</param>
    /// <param name="WorksheetName">Receives the worksheet name.</param>
    /// <param name="LocationCode">Receives the location code.</param>
    internal procedure ReadWorksheetKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var IsPick: Boolean; var TemplateName: Code[10]; var WorksheetName: Code[10]; var LocationCode: Code[10])
    var
        Context: Codeunit "Whse Write Context ori";
        TypeText: Text;
        TemplateText: Text;
        NameText: Text;
        LocationText: Text;
        SubjectText: Text;
        TypePresent: Boolean;
        TemplatePresent: Boolean;
        NamePresent: Boolean;
        LocationPresent: Boolean;
        MissingLbl: Label '%1 is required.', Comment = '%1 = parameter, is-IS=%1 er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send worksheetType, worksheetTemplateName, worksheetName and locationCode.', Comment = 'is-IS=Sendu worksheetType, worksheetTemplateName, worksheetName og locationCode.';
        TypeLbl: Label 'worksheetType %1 is not pick or putAway.', Comment = '%1 = value, is-IS=worksheetType %1 er hvorki pick né putAway.';
        TypeNextStepLbl: Label 'Send worksheetType pick or putAway.', Comment = 'is-IS=Sendu worksheetType pick eða putAway.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
    begin
        IsPick := false;
        Clear(TemplateName);
        Clear(WorksheetName);
        Clear(LocationCode);
        Context.ReadText(RequestJson, 'worksheetType', 20, Argument, TypeText, TypePresent, 'worksheetType');
        Context.ReadText(RequestJson, 'worksheetTemplateName', MaxStrLen(TemplateName), Argument, TemplateText, TemplatePresent, 'worksheetTemplateName');
        Context.ReadText(RequestJson, 'worksheetName', MaxStrLen(WorksheetName), Argument, NameText, NamePresent, 'worksheetName');
        Context.ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, LocationPresent, 'locationCode');
        if Argument.HasCollectedErrors() then
            exit;
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if LocationPresent and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationText)) then
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, SubjectText, ConflictNextStepLbl);
        if not LocationPresent then
            LocationText := SubjectText;
        if StrLen(LocationText) > MaxStrLen(LocationCode) then
            LocationText := '';
        if not TypePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'worksheetType'), 'worksheetType', '', 'pick, putAway', MissingNextStepLbl)
        else
            case LowerCase(TypeText) of
                'pick':
                    IsPick := true;
                'putaway':
                    IsPick := false;
                else
                    Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeLbl, TypeText), 'worksheetType', TypeText, 'pick, putAway', TypeNextStepLbl);
            end;
        if not TemplatePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'worksheetTemplateName'), 'worksheetTemplateName', '', '', MissingNextStepLbl);
        if not NamePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'worksheetName'), 'worksheetName', '', '', MissingNextStepLbl);
        if LocationText = '' then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'locationCode'), 'locationCode', '', '', MissingNextStepLbl);
        TemplateName := CopyStr(TemplateText, 1, MaxStrLen(TemplateName));
        WorksheetName := CopyStr(NameText, 1, MaxStrLen(WorksheetName));
        LocationCode := CopyStr(LocationText, 1, MaxStrLen(LocationCode));
    end;

    /// <summary>
    /// Checks the location and its pick or put-away setup, the worksheet template and its type, and the worksheet name.
    /// Writes the refusal on Argument and returns false on the first failure.
    /// </summary>
    /// <param name="Argument">Receives the refusal.</param>
    /// <param name="IsPick">True for a pick worksheet.</param>
    /// <param name="TemplateName">Worksheet template name.</param>
    /// <param name="WorksheetName">Worksheet name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <returns>True when the worksheet can be used.</returns>
    internal procedure ResolveWorksheet(var Argument: Record "Message Argument ori"; IsPick: Boolean; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        WorksheetTemplate: Record "Whse. Worksheet Template";
        NameRecord: Record "Whse. Worksheet Name";
        LocationNotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        LocationNextStepLbl: Label 'Check the location code and send the request again.', Comment = 'is-IS=Athugaðu staðsetningarkóðann og sendu beiðnina aftur.';
        NoPickLbl: Label 'Location %1 does not require pick and shipment, so it has no pick worksheet.', Comment = '%1 = location, is-IS=Staðsetning %1 krefst ekki tínslu og afhendingar, svo hún hefur ekkert tínsluvinnublað.';
        NoPutAwayLbl: Label 'Location %1 does not require put-away and receipt, so it has no put-away worksheet.', Comment = '%1 = location, is-IS=Staðsetning %1 krefst ekki frágangs og móttöku, svo hún hefur ekkert frágangsvinnublað.';
        InventoryNextStepLbl: Label 'Use the inventory activities instead.', Comment = 'is-IS=Notaðu birgðaaðgerðirnar í staðinn.';
        NotFoundLbl: Label 'Worksheet template %1 or worksheet %2 was not found at location %3.', Comment = '%1 = template, %2 = name, %3 = location, is-IS=Vinnublaðssniðmát %1 eða vinnublað %2 fannst ekki á staðsetningu %3.';
        NotFoundNextStepLbl: Label 'Create the worksheet name first.', Comment = 'is-IS=Stofnaðu nafn vinnublaðsins fyrst.';
        TypeLbl: Label 'Worksheet template %1 is not a %2 worksheet template.', Comment = '%1 = template, %2 = worksheetType, is-IS=Vinnublaðssniðmát %1 er ekki %2-sniðmát.';
        TypeNextStepLbl: Label 'Use a worksheet template of the type named by worksheetType.', Comment = 'is-IS=Notaðu vinnublaðssniðmát af þeirri tegund sem worksheetType nefnir.';
    begin
        Location.SetLoadFields(Code, "Require Pick", "Require Shipment", "Require Put-away", "Require Receive");
        if not Location.Get(LocationCode) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(LocationNotFoundLbl, LocationCode), 'locationCode', LocationCode, '', LocationNextStepLbl);
            exit(false);
        end;
        if IsPick and not (Location."Require Pick" and Location."Require Shipment") then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoPickLbl, LocationCode), 'locationCode', LocationCode, '', InventoryNextStepLbl);
            exit(false);
        end;
        if (not IsPick) and not (Location."Require Put-away" and Location."Require Receive") then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoPutAwayLbl, LocationCode), 'locationCode', LocationCode, '', InventoryNextStepLbl);
            exit(false);
        end;
        WorksheetTemplate.SetLoadFields(Name, Type);
        if not WorksheetTemplate.Get(TemplateName) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, TemplateName, WorksheetName, LocationCode), 'worksheetTemplateName', TemplateName, '', NotFoundNextStepLbl);
            exit(false);
        end;
        if (IsPick and (WorksheetTemplate.Type <> WorksheetTemplate.Type::Pick)) or ((not IsPick) and (WorksheetTemplate.Type <> WorksheetTemplate.Type::"Put-away")) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeLbl, TemplateName, WorksheetTypeName(IsPick)), 'worksheetTemplateName', TemplateName, WorksheetTypeName(IsPick), TypeNextStepLbl);
            exit(false);
        end;
        NameRecord.SetLoadFields("Worksheet Template Name", Name, "Location Code");
        if not NameRecord.Get(TemplateName, WorksheetName, LocationCode) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, TemplateName, WorksheetName, LocationCode), 'worksheetName', WorksheetName, '', NotFoundNextStepLbl);
            exit(false);
        end;
        exit(true);
    end;

    /// <summary>Filters worksheet lines on one worksheet.</summary>
    /// <param name="WorksheetLine">The record to filter.</param>
    /// <param name="TemplateName">Worksheet template name.</param>
    /// <param name="WorksheetName">Worksheet name.</param>
    /// <param name="LocationCode">Location code.</param>
    internal procedure FilterWorksheet(var WorksheetLine: Record "Whse. Worksheet Line"; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10])
    begin
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, WorksheetName);
        WorksheetLine.SetRange("Location Code", LocationCode);
    end;

    /// <summary>Returns the highest worksheet line number, or zero.</summary>
    /// <param name="TemplateName">Worksheet template name.</param>
    /// <param name="WorksheetName">Worksheet name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <returns>The last line number.</returns>
    internal procedure LastLineNo(TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]): Integer
    var
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        FilterWorksheet(WorksheetLine, TemplateName, WorksheetName, LocationCode);
        WorksheetLine.SetLoadFields("Line No.");
        if WorksheetLine.FindLast() then
            exit(WorksheetLine."Line No.");
        exit(0);
    end;

    /// <summary>Writes one worksheet line as JSON.</summary>
    /// <param name="WorksheetLine">The line.</param>
    /// <returns>The line object.</returns>
    internal procedure LineJson(WorksheetLine: Record "Whse. Worksheet Line"): JsonObject
    var
        LineObject: JsonObject;
    begin
        LineObject.Add('lineNo', WorksheetLine."Line No.");
        LineObject.Add('whseDocumentType', Enum::"Warehouse Worksheet Document Type".Names().Get(Enum::"Warehouse Worksheet Document Type".Ordinals().IndexOf(WorksheetLine."Whse. Document Type".AsInteger())));
        LineObject.Add('whseDocumentNo', WorksheetLine."Whse. Document No.");
        LineObject.Add('whseDocumentLineNo', WorksheetLine."Whse. Document Line No.");
        LineObject.Add('itemNo', WorksheetLine."Item No.");
        LineObject.Add('variantCode', WorksheetLine."Variant Code");
        LineObject.Add('unitOfMeasureCode', WorksheetLine."Unit of Measure Code");
        LineObject.Add('quantity', WorksheetLine.Quantity);
        LineObject.Add('qtyOutstanding', WorksheetLine."Qty. Outstanding");
        LineObject.Add('qtyToHandle', WorksheetLine."Qty. to Handle");
        LineObject.Add('fromBin', WorksheetLine."From Bin Code");
        LineObject.Add('toBin', WorksheetLine."To Bin Code");
        exit(LineObject);
    end;

    /// <summary>Returns the worksheetType text of a worksheet.</summary>
    /// <param name="IsPick">True for a pick worksheet.</param>
    /// <returns>pick or putAway.</returns>
    internal procedure WorksheetTypeName(IsPick: Boolean): Text
    begin
        if IsPick then
            exit('pick');
        exit('putAway');
    end;

    /// <summary>The pick and put-away worksheet flow.</summary>
    /// <param name="Workflow">Receives the workflow chapter.</param>
    internal procedure WorksheetWorkflow(var Workflow: JsonObject)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Worksheet.GetDocuments', 'Fill the pick or put-away worksheet from released shipments or posted receipts.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Worksheet.CreateActivities', 'Create picks or put-aways from the worksheet lines with quantity to handle.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Pick.Register', 'Register a pick; Warehouse.Putaway.Register registers a put-away.'));
        Workflow.Add('steps', Steps);
    end;
}
