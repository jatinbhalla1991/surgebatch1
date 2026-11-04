output "sdk_auth" {
  value = jsonencode({
    clientId                     = azuread_application.github_aks.application_id
    clientSecret                 = azuread_service_principal_password.github_aks.value
    subscriptionId               = data.azurerm_client_config.current.subscription_id
    tenantId                     = data.azurerm_client_config.current.tenant_id
    activeDirectoryEndpointUrl   = "https://login.microsoftonline.com"
    resourceManagerEndpointUrl   = "https://management.azure.com/"
    activeDirectoryGraphResourceId = "https://graph.windows.net/"
    sqlManagementEndpointUrl     = "https://management.core.windows.net:8443/"
    galleryEndpointUrl           = "https://gallery.azure.com/"
    managementEndpointUrl        = "https://management.core.windows.net/"
  })
  sensitive = true
}
