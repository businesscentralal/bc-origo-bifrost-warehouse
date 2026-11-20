namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InternalDocument;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.InternalPick.Create (#106).
/// Validates the request, then creates, releases and optionally turns the internal pick into a pick in Codeunit.Run isolation.
/// A basic location is refused so this type never writes outside directed put-away and pick.
/// </summary>
codeunit 10078484 "Whse IntPick Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Internal Doc Helper ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The internal pick payload was empty.', Comment = 'is-IS=Gögnin til að stofna innri tínslu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Helper.CreatePick(Payload, Result);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can create an internal pick and its pick.</summary>
    /// <returns>True when the caller can write the internal document and the warehouse activity.</returns>
    procedure IsEnabled(): Boolean
    var
        Header: Record "Whse. Internal Pick Header";
        Line: Record "Whse. Internal Pick Line";
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
    begin
        exit(Header.WritePermission() and Line.WritePermission() and ActivityHeader.WritePermission() and ActivityLine.WritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The internal document header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Whse. Internal Pick Header");
    end;

    /// <summary>Returns a short description of Warehouse.InternalPick.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates an internal pick to a bin at a directed location, and optionally the pick.', Comment = 'is-IS=Stofnar innri tínslu í hólf á beinni staðsetningu og valfrjálst tínslu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'internal pick, pick to bin, replenish production bin, stage stock, directed pick', Comment = 'is-IS=innri tínsla, tína í hólf, fylla á framleiðsluhólf, taka til birgðir, bein tínsla';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Creates and releases an internal pick at a directed location. Use Warehouse.InventoryMovement.Create for a location without directed put-away and pick.', Comment = 'is-IS=Stofnar og gefur út innri tínslu á beinni staðsetningu. Notaðu Warehouse.InventoryMovement.Create fyrir staðsetningu án beinnar innsetningar og tínslu.';
    begin
        exit(SelectionLbl);
    end;

    /// <summary>Returns the subject envelope.</summary>
    /// <param name="Envelope">Receives the envelope.</param>
    /// <returns>True when the envelope is used.</returns>
    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('location code');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A location code selects the same location as locationCode. Do not send a different location in both places.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The directed location the internal pick belongs to.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The directed location the internal pick belongs to.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        LineChildren: JsonArray;
        LinesParameter: JsonObject;
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Directed put-away and pick location. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('toZoneCode', 'string', false, 'Zone the stock is picked to. Optional; taken from toBinCode when that is sent.'));
        Parameters.Add(ContractMgt.Parameter('toBinCode', 'string', false, 'Bin the stock is picked to.'));
        Parameters.Add(ContractMgt.Parameter('dueDate', 'string', false, 'Due date of the internal pick, as YYYY-MM-DD. Optional.'));
        Parameters.Add(ContractMgt.Parameter('release', 'boolean', false, 'Releases the internal pick after the lines are written. Default true.'));
        Parameters.Add(ContractMgt.Parameter('createActivity', 'boolean', false, 'Also creates the pick from the released internal pick. Default false. Needs release true.'));
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'Warehouse employee the pick is assigned to. Only with createActivity true.'));
        Parameters.Add(ContractMgt.Parameter('sortingMethod', 'string', false, 'Sorting method of the pick, for example Item or Bin. Only with createActivity true.'));
        LinesParameter := ContractMgt.Parameter('lines', 'array', false, 'Lines to pick. At least one line is required.');
        LineChildren.Add(ContractMgt.Parameter('itemNo', 'string', true, 'Item number.'));
        LineChildren.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Item variant. Optional.'));
        LineChildren.Add(ContractMgt.Parameter('unitOfMeasureCode', 'string', false, 'Unit of measure. Defaults to the item base unit.'));
        LineChildren.Add(ContractMgt.Parameter('quantity', 'number', true, 'Quantity in the line unit of measure. Must be greater than zero.'));
        LineChildren.Add(ContractMgt.Parameter('lotNo', 'string', false, 'Lot number to pick. Optional.'));
        LineChildren.Add(ContractMgt.Parameter('serialNo', 'string', false, 'Serial number to pick. Optional; the line base quantity must then be 1.'));
        LineChildren.Add(ContractMgt.Parameter('packageNo', 'string', false, 'Package number to pick. Optional.'));
        LinesParameter.Add('children', LineChildren);
        Parameters.Add(LinesParameter);
        exit(true);
    end;

    /// <summary>Returns the response chapter.</summary>
    /// <param name="Response">Receives the response.</param>
    /// <returns>True when a response is declared.</returns>
    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        LineFields: JsonArray;
        Lines: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('internalDocumentNo', 'string', 'Number of the created internal pick.'));
        Fields.Add(ContractMgt.ResponseField('systemId', 'string', 'SystemId of the created internal pick.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        Fields.Add(ContractMgt.ResponseField('documentStatus', 'string', 'Status of the internal pick: Open or Released.'));
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of lines on the internal pick.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Item variant.'));
        LineFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity on the line.'));
        LineFields.Add(ContractMgt.ResponseField('toZoneCode', 'string', 'Zone the line is picked to.'));
        LineFields.Add(ContractMgt.ResponseField('toBinCode', 'string', 'Bin the line is picked to.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Lines of the internal pick.');
        Lines.Add('children', LineFields);
        Fields.Add(Lines);
        Fields.Add(ContractMgt.ResponseField('activityType', 'string', 'With createActivity: Pick.'));
        Fields.Add(ContractMgt.ResponseField('activityNo', 'string', 'With createActivity: number of the created pick.'));
        Fields.Add(ContractMgt.ResponseField('activitySystemId', 'string', 'With createActivity: SystemId of the created pick.'));
        Fields.Add(ContractMgt.ResponseField('totalLines', 'integer', 'With createActivity: number of take and place lines on the pick.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        Parts: Codeunit "Whse Contract Parts ori";
        UnknownParameterNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick.', 'Use Warehouse.InventoryMovement.Create for basic warehouse locations.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The to-bin is blocked for movement, or Business Central refuses the bin, the quantity available to pick or the pick.', 'Read the returned text, correct the bin, the bin content or the quantity, and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The location, zone, bin, item, variant, unit of measure or warehouse employee was not found.', 'Check the code with Warehouse.BinContent.Get or Warehouse.Bin.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'locationCode, lines, itemNo or quantity is missing.', 'Send locationCode and at least one line with itemNo and quantity.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'A quantity is zero or negative, createActivity is sent with release false, assignedUserId or sortingMethod is sent without createActivity, or sortingMethod is not known.', 'Correct the value as the error text says.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes, numbers for quantities and true or false for switches.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', UnknownParameterNextStepLbl);
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations, or toBinCode is not in toZoneCode.', 'Send one location, and a zone that holds the bin.');
        Parts.AddPermissionError(Errors, 'BIFROST Whse - Full ori');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one problem was found.', 'Correct every listed problem and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the internal pick or the pick.', 'Read the returned text, correct the bin, the bin content or the quantity, and send the request again. Nothing was written.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Creates and by default releases an internal pick, and with createActivity also creates the pick. Nothing is registered; registering is a separate step.', 'BIFROST Whse - Full ori', false);
        exit(true);
    end;

    /// <summary>Returns the metering chapter.</summary>
    /// <param name="Metering">Receives the metering.</param>
    /// <returns>False. This type is not metered.</returns>
    procedure GetMetering(var Metering: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns related message types.</summary>
    /// <param name="Related">Receives the related types.</param>
    /// <returns>True when related types are declared.</returns>
    procedure GetRelated(var Related: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it to register the pick created with createActivity.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Worksheet.GetDocuments', 'Use it to bring a released internal pick into a worksheet instead of createActivity.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the bin content before you send the lines.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Movement.Create', 'Use it to move between two bins you choose yourself.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True. The workflow runs from the bin content check to registration.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.BinContent.Get', 'Read the bin content so no line asks for more than the bin holds.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.InternalPick.Create', 'Create and release the internal pick, with createActivity true to get the pick at once.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Activity.Get', 'Read the pick lines and check the bins Business Central chose.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Pick.Register', 'Register the pick.'));
        Workflow.Add('steps', Steps);
        exit(true);
    end;

    /// <summary>Returns an example request and response.</summary>
    /// <param name="Examples">Receives the examples.</param>
    /// <returns>True when an example is declared.</returns>
    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example('Pick ten pieces to a production bin', '{"locationCode":"WHITE","toBinCode":"W-07-0001","lines":[{"itemNo":"1896-S","quantity":10}],"createActivity":true}', '{"status":"Success","internalDocumentNo":"IPI000001","locationCode":"WHITE","documentStatus":"Released","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"1896-S","variantCode":"","unitOfMeasureCode":"PCS","quantity":10,"toZoneCode":"PRODUCTION","toBinCode":"W-07-0001"}],"activityType":"Pick","activityNo":"PI000001","totalLines":2}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Creates an internal pick at a directed location for stock that no source document asks for, releases it and can create the pick. Business Central chooses the take bins.', Comment = 'is-IS=Stofnar innri tínslu á beinni staðsetningu fyrir birgðir sem ekkert upprunaskjal biður um, gefur hana út og getur stofnað tínslu. Business Central velur hólfin sem tekið er úr.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes hold the edge cases.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Only a location with directed put-away and pick is accepted. A basic location is refused with PreconditionFailed and nothing else is checked; use Warehouse.InventoryMovement.Create there. ' +
            'Send toBinCode (and optionally toZoneCode and dueDate) and at least one line. A to-bin blocked for all or inbound movement is refused. The quantity available to pick is checked by Business Central when the pick is created; when it is short, Business Central refuses and nothing is written. ' +
            'Every problem in the request is reported together and nothing is written. The internal document, its release and the pick are written in one transaction; when Business Central refuses any part, nothing is left behind and the answer carries Business Central''s own text. ' +
            'With createActivity false the released internal pick waits for Warehouse.Worksheet.GetDocuments. With createActivity true Business Central chooses the take bins by its own rules. Register the pick with Warehouse.Pick.Register.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the request and creates the internal pick, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Internal Doc Helper ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        Result: JsonObject;
        ErrorText: Text;
        DeniedLbl: Label 'You do not have permission to create an internal pick.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna innri tínslu.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
    begin
        Context.Reset();
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        Helper.ReadRequest(RequestJson, Argument, true, false, Payload);
        Helper.ReadPickDueDate(RequestJson, Argument, Payload);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse IntPick Create Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse IntPick Create Impl ori") then begin
                ErrorText := GetLastErrorText();
                // Business Central commits parts of the work before it can refuse; remove them so nothing is left behind.
                Helper.RemovePendingDocument(true);
                Context.Reset();
                Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, ErrorText, '', '', '', Helper.RefusedNextStep());
                exit;
            end;
        if not Context.TryGetResult(Result) then begin
            Context.Reset();
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, ProblemsLbl, 'internalDocumentNo', '', '', Helper.RefusedNextStep());
            exit;
        end;
        Helper.WriteResponse(Argument, Result, true);
        Context.Reset();
    end;
}
