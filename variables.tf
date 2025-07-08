variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  default = "eastus"
}

variable "rg_ws_name" {
  default = "rg-dbw"
}

variable "rg_tr_name" {
  default = "rg-transit"
}

variable "vnet_ws_name" {
  default = "vnet-dbw"
}

variable "vnet_tr_name" {
  default = "vnet-transit"
}

variable "vnet_ws_cidr" {
  default = "10.1.0.0/16"
}

variable "vnet_tr_cidr" {
  default = "10.2.0.0/16"
}

variable "ws_subnets" {
  type = map(string)
  default = {
    public   = "10.1.0.0/24"
    private  = "10.1.1.0/24"
    endpoint = "10.1.2.0/27"
  }
}

variable "tr_subnets" {
  type = map(string)
  default = {
    public  = "10.2.0.0/24"
    private = "10.2.1.0/24"
  }
}

variable "tr_subnet_cidr" {
  default = "10.2.0.0/24"
}
