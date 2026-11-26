namespace Origo.Bifrost.Warehouse;

using Microsoft.Service.Document;
using Origo.Bifrost;
using System.Environment.Configuration;

/// <summary>Checks service-source availability without changing plans or permissions.</summary>
codeunit 10078444 "Whse Service Source ori"
{
    Access = Internal;

    /// <summary>Returns whether the company and caller can use service documents.</summary>
    internal procedure IsAvailable(): Boolean
    var
        ServiceHeader: Record "Service Header";
        ServiceLine: Record "Service Line";
        ApplicationAreaMgmtFacade: Codeunit "Application Area Mgmt. Facade";
    begin
        if not ApplicationAreaMgmtFacade.IsPremiumExperienceEnabled() then
            exit(false);
        exit(ServiceHeader.ReadPermission() and ServiceLine.ReadPermission());
    end;

    /// <summary>Collects a localized refusal before service data is read.</summary>
    internal procedure CheckAvailable(var Argument: Record "Message Argument ori"; ParameterName: Text; SourceValue: Text): Boolean
    begin
        if IsAvailable() then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, UnavailableText(), ParameterName, SourceValue, 'Service Order', NextStepText());
        exit(false);
    end;

    /// <summary>Returns the service-source precondition text.</summary>
    internal procedure UnavailableText(): Text
    var
        UnavailableLbl: Label 'Service orders require the Premium experience, a plan that permits service management and permission to read service documents.', Comment = 'is-IS=Þjónustupantanir krefjast Premium-viðmóts, áskriftar sem heimilar þjónustustjórnun og heimildar til að lesa þjónustuskjöl.';
    begin
        exit(UnavailableLbl);
    end;

    /// <summary>Returns the corrective action for service-source availability.</summary>
    internal procedure NextStepText(): Text
    var
        NextStepLbl: Label 'Ask an administrator to enable the Premium experience and assign a Premium plan and service document permissions, or use a supported non-service source.', Comment = 'is-IS=Biddu stjórnanda um að virkja Premium-viðmót og úthluta Premium-áskrift og heimildum fyrir þjónustuskjöl, eða notaðu studdan uppruna sem er ekki þjónustupöntun.';
    begin
        exit(NextStepLbl);
    end;
}
