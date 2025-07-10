provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "transit" {
  name     = var.rg_transit_name
  location = var.location
}

resource "azurerm_resource_group" "main" {
  name     = var.rg_main_name
  location = var.location
}
