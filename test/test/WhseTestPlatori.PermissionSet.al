namespace Origo.Bifrost.Warehouse.Test;

using System.Environment.Configuration;

/// <summary>
/// Platform-only baseline for the restricted licence-admin setup regression (#90).
/// It grants no Bifrost or Warehouse object permission.
/// </summary>
permissionset 97005 "Whse Test Plat ori"
{
    Assignable = true;
    Caption = 'Warehouse test platform', Locked = true;
    IncludedPermissionSets = "Guided Experience - View";
    Permissions = tabledata "NAV App Setting" = r;
}
