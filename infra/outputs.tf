output "fqdn" {
  description = "Public FQDN of the demo host: <dns_label>.<location>.cloudapp.azure.com."
  value       = azurerm_public_ip.main.fqdn
}

output "public_ip_address" {
  description = "Static public IP address of the demo host."
  value       = azurerm_public_ip.main.ip_address
}

output "vm_name" {
  description = "Name of the virtual machine running the stack."
  value       = azurerm_linux_virtual_machine.main.name
}

output "resource_group_name" {
  description = "Resource group that holds the stack."
  value       = data.azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region of the stack."
  value       = data.azurerm_resource_group.main.location
}
