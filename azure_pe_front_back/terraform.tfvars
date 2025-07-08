subscription_id  = "edd4cc45-85c7-4aec-8bf5-648062d519bf"
location         = "eastus"

rg_ws_name       = "rg-dbw"
rg_tr_name       = "rg-transit"

vnet_ws_name     = "vnet-dbw"
vnet_tr_name     = "vnet-transit"

vnet_ws_cidr     = "10.1.0.0/16"
vnet_tr_cidr     = "10.2.0.0/16"
tr_subnet_cidr   = "10.2.0.0/24"

ws_subnets = {
  public   = "10.1.0.0/24"
  private  = "10.1.1.0/24"
  endpoint = "10.1.2.0/27"
}

tr_subnets = {
  public  = "10.2.0.0/24"
  private = "10.2.1.0/24"
}
