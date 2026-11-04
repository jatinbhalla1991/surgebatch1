resource "azurerm_mssql_database" "example" {
  name                = var.sql_db_name
  server_id           = var.sql_server_id
  sku_name            = "Basic"

  tags = {
    environment = "dev"
  }
}