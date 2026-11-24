# disk.tf — disque de données persistant, attaché à la VM au LUN 0.
#
# Il porte l'état de la démo (Traefik, Prometheus, Grafana) créé par cloud-init.
# Formatage et montage sont faits par cloud-init, pas par Terraform.
resource "azurerm_managed_disk" "data" {
  name                 = "${var.prefix}-data-disk"
  location             = var.location
  resource_group_name  = data.azurerm_resource_group.main.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = var.tags

  # Contient l'état de la démo qui doit survivre à une reconstruction de la VM.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = 0
  caching            = "None"
}
