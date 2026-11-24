resource "azurerm_managed_disk" "data" {
  name                 = "${var.prefix}-data-disk"
  location             = var.location
  resource_group_name  = data.azurerm_resource_group.main.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = var.tags

  # Holds demo state that must survive a rebuild of the VM.
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
