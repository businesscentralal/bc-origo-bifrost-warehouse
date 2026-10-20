namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Shared contract chapters for the Warehouse message types.
/// </summary>
codeunit 10078459 "Whse Contract Parts ori"
{
    Access = Internal;

    internal procedure RecordEnvelope(SubjectForms: List of [Text]; SubjectDescription: Text; DataRequired: Boolean): JsonObject
    var
        Envelope: JsonObject;
        Subject: JsonObject;
        Forms: JsonArray;
        Form: Text;
    begin
        foreach Form in SubjectForms do
            Forms.Add(Form);
        Subject.Add('use', 'optional');
        Subject.Add('forms', Forms);
        Subject.Add('description', SubjectDescription);
        Envelope.Add('subject', Subject);
        Envelope.Add('dataRequired', DataRequired);
        Envelope.Add('version', '1.0');
        Envelope.Add('contentType', 'text/json');
        exit(Envelope);
    end;

    internal procedure RecordTarget(RecordName: Text; DataKeys: Text): JsonArray
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Target: JsonArray;
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the ' + RecordName + '.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the ' + RecordName + '.'));
        Target.Add(ContractMgt.TargetEntry('data.' + DataKeys, 'guid or document no.', 'The identifier keys accepted for the ' + RecordName + '. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(Target);
    end;

    internal procedure ActivityTarget(ActivityName: Text; NumberKey: Text): JsonArray
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Target: JsonArray;
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the Warehouse Activity Header.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'activity no.', 'The number of the ' + ActivityName + '.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.recordSystemId, data.id', 'guid', 'The SystemId of the Warehouse Activity Header.'));
        Target.Add(ContractMgt.TargetEntry('data.' + NumberKey + ', data.no', 'activity no.', 'The number of the ' + ActivityName + '.'));
        exit(Target);
    end;

    internal procedure AddPagingParameters(var Parameters: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('skip', 'integer', false, 'Number of matching records to skip. Defaults to 0.'));
        Parameters.Add(ContractMgt.Parameter('take', 'integer', false, 'Maximum number of records to return. Defaults to the platform page size.'));
    end;

    /// <summary>Lists required document lookup errors, including strict JSON format validation.</summary>
    internal procedure AddLookupErrors(var Errors: JsonArray; RecordName: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::MissingParameter, 'No ' + RecordName + ' identifier was supplied.', 'Send subject or an identifier under data.'));
        AddRecordNotFoundError(Errors, RecordName);
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::ConflictingIdentifiers, 'Two identifiers point to different records.', 'Send one identifier or identifiers for the same record.'));
        AddIdentifierFormatErrors(Errors);
    end;

    /// <summary>Lists optional lookup errors; callers add any supported conflict error.</summary>
    internal procedure AddOptionalLookupErrors(var Errors: JsonArray; RecordName: Text)
    begin
        AddRecordNotFoundError(Errors, RecordName);
        AddIdentifierFormatErrors(Errors);
    end;

    local procedure AddRecordNotFoundError(var Errors: JsonArray; RecordName: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::RecordNotFound, 'The supplied identifier does not match a ' + RecordName + '.', 'Check the value or look the record up first.'));
    end;

    local procedure AddIdentifierFormatErrors(var Errors: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, 'data is not a JSON object, an identifier key under data is not a JSON string, or a SystemId is not a GUID. The parameter names the offending key.', 'Send data as an object, identifier keys as strings, and SystemId keys as GUIDs.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::MultipleErrors, 'Several identifier values have an invalid format.', 'Read errors in order and correct each named key.'));
    end;

    /// <summary>
    /// Lists the errors of Warehouse.Receipt.Post and Warehouse.Shipment.Post. Each entry carries the nextStep the
    /// answer gives, and InvalidParameterFormat names the line values of the wrong JSON type as well (#54 AC11).
    /// </summary>
    /// <param name="Errors">Receives the entries.</param>
    /// <param name="RecordName">The document table caption, e.g. Warehouse Receipt Header.</param>
    /// <param name="IdentifierKeys">The identifier keys under data, comma separated.</param>
    /// <param name="QtyKey">The line quantity key: qtyToReceive or qtyToShip.</param>
    /// <param name="IsShipment">True for the shipment, which also refuses a quantity above the picked quantity.</param>
    internal procedure AddDocumentPostErrors(var Errors: JsonArray; RecordName: Text; IdentifierKeys: Text; QtyKey: Text; IsShipment: Boolean)
    var
        PreconditionWhen: Text;
        PreconditionNextStep: Text;
    begin
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::MissingParameter,
            'No ' + RecordName + ' identifier was sent, or a line has no lineNo or no ' + QtyKey + '.',
            'Send the number or SystemId as the subject, or in one of: ' + IdentifierKeys + '. Send lineNo and ' + QtyKey + ' on every line.'));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::RecordNotFound,
            'An identifier that was sent does not match a ' + RecordName + ', also when another identifier matches one. The parameter names the key.',
            'Check the number with Data.Records.Get on table ' + RecordName + '. For a SystemId, check the SystemId the same way.'));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::ConflictingIdentifiers,
            'Two identifiers point to different records.',
            'Send only one identifier, or identifiers for the same record.'));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::InvalidParameterFormat,
            'data is not a JSON object, an identifier key under data is not a JSON string, a SystemId is not a GUID, lines is not an array of objects, or a line value has the wrong JSON type: lineNo must be an integer and ' + QtyKey + ' a number. The parameter names the offending key, e.g. lines[0].' + QtyKey + '.',
            'Send data as an object with the identifier keys as strings, and each line as an object with lineNo as an integer and ' + QtyKey + ' as a number.'));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::MultipleErrors,
            'More than one value failed validation, for example an unknown key together with problems in the lines. errors[] lists each one with its own code.',
            'Correct every listed value and send the request again. Nothing was posted.'));
        if IsShipment then
            Errors.Add(NextStepEntry("Bifrost Error Code ori"::PermissionDenied,
                'The caller lacks BIFROST WhsePost ori, or invoice is true and the caller lacks BIFROST WhseInv ori.',
                'Ask an administrator to assign the BIFROST WhsePost ori permission set, and BIFROST WhseInv ori to invoice.'))
        else
            Errors.Add(NextStepEntry("Bifrost Error Code ori"::PermissionDenied,
                'The caller lacks BIFROST WhsePost ori.',
                'Ask an administrator to assign the BIFROST WhsePost ori permission set.'));
        if IsShipment then begin
            PreconditionWhen := 'The Warehouse Shipment has no lines, every line would ship zero, or qtyToShip is above the picked quantity at a location that requires pick.';
            PreconditionNextStep := 'Set a quantity above zero on at least one line, or register the pick first.';
        end else begin
            PreconditionWhen := 'The Warehouse Receipt has no lines, or every line would receive zero.';
            PreconditionNextStep := 'Set a quantity above zero on at least one line.';
        end;
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::PreconditionFailed, PreconditionWhen, PreconditionNextStep));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::InvalidLine,
            'A lineNo is not on the document or is listed twice, or ' + QtyKey + ' is negative or above the outstanding quantity.',
            'Read the lines first, send each line once, and read the outstanding quantity on the line and lower it.'));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::UnknownParameter,
            'The request or a line contains a key this type does not accept.',
            'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.'));
        Errors.Add(NextStepEntry("Bifrost Error Code ori"::BusinessCentralError,
            'Business Central''s own error text. Typical causes: invalid quantities, posting setup or source-document state.',
            'Read the returned text; it names the field or setup to fix.'));
    end;

    local procedure NextStepEntry(ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text) Entry: JsonObject
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
    end;

    internal procedure AddBusinessCentralError(var Errors: JsonArray; TypicalCauses: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::BusinessCentralError, 'Business Central''s own error text.', 'Read the returned text; it names the field or setup to fix. Typical causes: ' + TypicalCauses));
    end;

    internal procedure AddPermissionError(var Errors: JsonArray; PermissionSetName: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PermissionDenied, 'The caller lacks ' + PermissionSetName + '.', 'Ask an administrator to assign ' + PermissionSetName + '.'));
    end;

    internal procedure AddSourceDocumentErrors(var Errors: JsonArray; SourceKinds: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.TextErrorEntry('sourceDocuments is required and must contain at least one entry.', 'The request has no source documents.', 'Send at least one source document.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::RecordNotFound, 'A source document does not exist.', 'Check each sourceType and documentNo.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'A source document is not Released or cannot be routed to a warehouse document.', 'Release the source and enable the required location routing.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, 'sourceType is not one of: ' + SourceKinds + '.', 'Use one of the documented sourceType values.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected source document creation.', 'Read the returned error text and correct the source document or setup.'));
    end;

    internal procedure AddActivityParameters(var Parameters: JsonArray; IncludeOptions: Boolean)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'User assigned to the created Warehouse Activity Header.'));
        Parameters.Add(ContractMgt.Parameter('sortingMethod', 'string', false, 'Warehouse activity sorting method.'));
        if IncludeOptions then begin
            Parameters.Add(ContractMgt.Parameter('setBreakbulkFilter', 'boolean', false, 'Must be false; true is rejected because the report request-page option is not supported.'));
            Parameters.Add(ContractMgt.Parameter('doNotFillQtyToHandle', 'boolean', false, 'Must be false; true is rejected because the report request-page option is not supported.'));
        end;
    end;

    internal procedure ReadEffect(var Effect: JsonObject; Changes: Text; PermissionSetName: Text)
    begin
        Effect.Add('effect', 'read');
        Effect.Add('changes', Changes);
        Effect.Add('idempotent', true);
        Effect.Add('permissionSet', PermissionSetName);
    end;

    internal procedure WriteEffect(var Effect: JsonObject; Changes: Text; PermissionSetName: Text; Idempotent: Boolean)
    begin
        Effect.Add('effect', 'write');
        Effect.Add('changes', Changes);
        Effect.Add('idempotent', Idempotent);
        Effect.Add('permissionSet', PermissionSetName);
    end;

    internal procedure IrreversibleEffect(var Effect: JsonObject; Changes: Text; PermissionSetName: Text)
    begin
        Effect.Add('effect', 'irreversible');
        Effect.Add('changes', Changes);
        Effect.Add('idempotent', false);
        Effect.Add('permissionSet', PermissionSetName);
    end;

    internal procedure Response(var ResponseJson: JsonObject; Fields: JsonArray)
    begin
        ResponseJson.Add('contentType', 'text/json');
        ResponseJson.Add('fields', Fields);
    end;

    internal procedure AddStatusField(var Fields: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Fields.Add(ContractMgt.ResponseField('status', 'string', 'Success on a successful call; Error responses use the standard error envelope.'));
    end;

    /// <summary>
    /// The inbound warehouse flow: receipt, receive posting, put-away.
    /// </summary>
    /// <param name="Workflow">Receives the workflow chapter.</param>
    internal procedure InboundWorkflow(var Workflow: JsonObject)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.Create', 'Create the Warehouse Receipt from a released Purchase Order, Sales Return Order or inbound Transfer Order.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.PreviewPost', 'Inspect the predicted entries without committing.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.Post', 'Post the receive; the source document is received, not invoiced.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Putaway.Create', 'Create the put-away from the Posted Warehouse Receipt when the location uses put-away.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Putaway.Register', 'Register the put-away to place the goods in their bins.'));
        Workflow.Add('steps', Steps);
    end;

    /// <summary>
    /// The outbound warehouse flow: shipment, pick, shipment posting.
    /// </summary>
    /// <param name="Workflow">Receives the workflow chapter.</param>
    internal procedure OutboundWorkflow(var Workflow: JsonObject)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Shipment.Create', 'Create the Warehouse Shipment from a released Sales Order or outbound Transfer Order.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Pick.Create', 'Create the pick from the Warehouse Shipment when the location uses picks.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Pick.Register', 'Register the pick; it updates the shipment quantities.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Shipment.PreviewPost', 'Inspect the predicted entries without committing.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Shipment.Post', 'Post the shipment, and optionally invoice the source document.'));
        Workflow.Add('steps', Steps);
    end;
}
