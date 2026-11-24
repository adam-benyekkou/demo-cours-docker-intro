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

  # Canonical:0001-com-ubuntu-server-noble:24_04-lts:latest (Ubuntu 24.04 LTS server).
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-noble"
    sku       = "24_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yml", {
    app_dir        = "/opt/demo-stack"
    admin_username = var.admin_username
    data_mount     = "/data"
    data_device    = "/dev/disk/azure/scsi1/lun0"
    git_url        = var.repo_url
    git_branch     = "main"
  }))

  lifecycle {
    ignore_changes = [custom_data]
  }
}
