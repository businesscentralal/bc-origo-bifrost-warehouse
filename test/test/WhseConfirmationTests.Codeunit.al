namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>Guards the counted-confirmation fixture helper without disabling Foundation's confirmation gate.</summary>
codeunit 97034 "Whse Confirmation Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Test Confirmation ori";

    /// <summary>A missing target reaches the same handler refusal after automatic or explicit confirmation.</summary>
    [Test]
    procedure PreviewCount_ReachesOriginalValidation()
    var
        AutomaticResponse: JsonObject;
        ExplicitResponse: JsonObject;
        RequestText: Text;
    begin
        // #93 AC1: a self-owned nonexistent target cannot mutate warehouse documents.
        RequestText := '{}';
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-93', RequestText, AutomaticResponse, false), 'Automatic confirmation returns JSON.');
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-93', '{"expectedCount":1}', ExplicitResponse, false), 'Explicit confirmation returns JSON.');
        Assert.AreEqual(ResponseCode(ExplicitResponse), ResponseCode(AutomaticResponse), 'Automatic confirmation must reach the same target validation.');
        Assert.AreNotEqual('ConfirmationRequired', ResponseCode(AutomaticResponse), 'The helper must confirm the preview.');
        Assert.AreEqual('{}', RequestText, 'The caller payload remains unchanged.');
    end;

    /// <summary>An explicit wrong count remains refused rather than being silently repaired.</summary>
    [Test]
    procedure ExplicitWrongCount_IsNotReplaced()
    var
        ResponseJson: JsonObject;
    begin
        // #93 AC1: Foundation's default one-record counter is checked before target lookup.
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-93', '{"expectedCount":0}', ResponseJson, false), 'Mismatch returns JSON.');
        Assert.AreEqual('ConfirmationMismatch', ResponseCode(ResponseJson), 'The helper must preserve explicit confirmation refusals.');
    end;

    /// <summary>An invalid count retains the original validation error.</summary>
    [Test]
    procedure InvalidCount_IsNotReplaced()
    var
        ResponseJson: JsonObject;
    begin
        // #93 AC1: invalid input cannot become a confirmed mutation.
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", 'X-NO-PICK-93', '{"expectedCount":-1}', ResponseJson, false), 'Invalid count returns JSON.');
        Assert.AreEqual('InvalidParameterFormat', ResponseCode(ResponseJson), 'The original invalid-count refusal remains.');
    end;

    local procedure ResponseCode(ResponseJson: JsonObject): Text
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(ResponseJson.Get('code', Token), 'A nonexistent fixture must return an error code.');
        exit(Token.AsValue().AsText());
    end;
}
