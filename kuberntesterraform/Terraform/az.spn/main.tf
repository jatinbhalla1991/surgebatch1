

data "azurerm_client_config" "current" {}

# (Optional) Define the resource group if not already created
data "azurerm_resource_group" "target" {
  name = var.resource_group_name
}

# Create Azure AD Application
resource "azuread_application" "github_aks" {
  display_name = "github-aks"
}

# Create SP for the Application
resource "azuread_service_principal" "github_aks" {
  client_id = azuread_application.github_aks.application_id
}

# Create SP Password
resource "azuread_service_principal_password" "github_aks" {
  service_principal_id = azuread_service_principal.github_aks.id
  value                = random_password.sp_password.result
  end_date_relative    = "8760h" # 1 year
}

# Generate random password
resource "random_password" "sp_password" {
  length  = 32
  special = true
}

# Assign Contributor role on the RG
resource "azurerm_role_assignment" "github_aks" {
  principal_id         = azuread_service_principal.github_aks.id
  role_definition_name = "Contributor"
  scope                = data.azurerm_resource_group.target.id
}