namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost.Warehouse;
using System.Environment.Configuration;

/// <summary>Test-only wizard execution and indirect HTTP-setting read; grants no settings write permission.</summary>
permissionset 97004 "Whse Wizard Test ori"
{
    Assignable = true;
    Caption = 'Whse Wizard Test', MaxLength = 30;
    Permissions = tabledata "NAV App Setting" = r,
                  codeunit "Whse Wizard Mgt ori" = X,
                  page "Whse Setup Wizard ori" = X;
}
