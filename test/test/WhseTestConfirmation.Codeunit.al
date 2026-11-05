namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;

/// <summary>Runs test dispatches through Foundation's counted-confirmation preview protocol.</summary>
codeunit 97033 "Whse Test Confirmation ori"
{
    /// <summary>Dispatches a fixture, confirming a no-write preview with its actual count.</summary>
    /// <param name="MessageType">The public message type.</param>
    /// <param name="Subject">The original subject.</param>
    /// <param name="RequestText">The original payload, never modified.</param>
    /// <param name="ResponseJson">The final response.</param>
    /// <param name="OmitCommit">The original transaction mode.</param>
    /// <returns>True when the dispatcher response parses as JSON.</returns>
    internal procedure RunMessage(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var ResponseJson: JsonObject; OmitCommit: Boolean): Boolean
    var
        RequestJson: JsonObject;
        ExpectedCountToken: JsonToken;
        ExpectedCount: Integer;
    begin
        if not SendRequest(MessageType, Subject, RequestText, ResponseJson, OmitCommit) then
            exit(false);
        if RequestText <> '' then
            if not RequestJson.ReadFrom(RequestText) then
                exit(true);
        if RequestJson.Contains('expectedCount') then
            exit(true);
        if ReadText(ResponseJson, 'code') <> 'ConfirmationRequired' then
            exit(true);
        if not ResponseJson.Get('expected', ExpectedCountToken) then
            exit(true);
        if not ExpectedCountToken.IsValue() then
            exit(true);
        if not Evaluate(ExpectedCount, ExpectedCountToken.AsValue().AsText()) then
            exit(true);

        // ConfirmationRequired guarantees that the first call changed nothing.
        // Preserve explicit confirmations, validation refusals and the caller's transaction mode.
        RequestJson.Add('expectedCount', ExpectedCount);
        RequestJson.WriteTo(RequestText);
        exit(SendRequest(MessageType, Subject, RequestText, ResponseJson, OmitCommit));
    end;

    local procedure SendRequest(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var ResponseJson: JsonObject; OmitCommit: Boolean): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseText: Text;
        SubjectText: Text[250];
    begin
        Clear(ResponseJson);
        SubjectText := CopyStr(Subject, 1, MaxStrLen(SubjectText));
        if RequestText <> '' then
            RequestContent.AddText(RequestText);
        Dispatcher.Execute(MessageType, Enum::"Message Version ori"::"1.0", SubjectText,
            'Bifrost Warehouse Tests', 'text/json', RequestContent, ResponseContent, ResponseContentType, OmitCommit);
        if ResponseContent.Length() = 0 then
            exit(false);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        exit(ResponseJson.ReadFrom(ResponseText));
    end;

    local procedure ReadText(ResponseJson: JsonObject; PropertyName: Text): Text
    var
        Token: JsonToken;
    begin
        if ResponseJson.Get(PropertyName, Token) then
            if Token.IsValue() then
                exit(Token.AsValue().AsText());
        exit('');
    end;
}
