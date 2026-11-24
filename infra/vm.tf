# vm.tf — la machine virtuelle Linux qui héberge la stack, avec son cloud-init.
#
# Seul compute de la démo : taille, image et clé de secours se règlent ici.
# custom_data est figé après création, d'où le ignore_changes.
resource "azurerm_linux_virtual_machine" "main" {
  name                            = "${var.prefix}-vm"
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  tags                            = var.tags

  network_interface_ids = [azurerm_network_interface.main.id]

  # Clé de secours uniquement : aucun port n'est ouvert, les déploiements passent
  # par run-command.
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
  # L'ancienne offre `0001-com-ubuntu-server-noble` n'est plus publiée dans
  # toutes les régions ; celle-ci se résout dans toutes les régions autorisées.
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
