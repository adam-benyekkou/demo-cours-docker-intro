resource "azurerm_linux_virtual_machine" "main" {
  name                            = "${var.prefix}-vm"
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  tags                            = var.tags

  network_interface_ids = [azurerm_network_interface.main.id]

  # Break-glass key only: no port is open, deploys go through run-command.
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  boot_diagnostics {}

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  # Canonical:ubuntu-24_04-lts:server:latest — Ubuntu 24.04 LTS, Gen2.
  # The older `0001-com-ubuntu-server-noble` offer is no longer published in
  # every region; this one resolves in every allowed region.
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yml", {
    data_mount  = "/data"
    data_device = "/dev/disk/azure/scsi1/lun0"
  }))

  lifecycle {
    ignore_changes = [custom_data]
  }
}
