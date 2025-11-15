resource "azurerm_storage_container" "homelab_container_vaultwarden_db_backup" {
  name                  = "vaultwarden-db-backup"
  storage_account_id    = azurerm_storage_account.homelab_storage_account.id
  container_access_type = "private"
}

data "azurerm_storage_account_sas" "homelab_container_vaultwarden_db_backup_sas" {
  connection_string = azurerm_storage_account.homelab_storage_account.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = "2025-11-01T00:00:00Z"
  expiry = "2125-11-01T00:00:00Z"

  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = true
    create  = true
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "azurerm_key_vault_secret" "homelab_container_vaultwarden_db_backup_connection_string" {
  name         = "vaultwarden-db-backup-connection-string"
  value        = data.azurerm_storage_account_sas.homelab_container_vaultwarden_db_backup_sas.connection_string
  key_vault_id = azurerm_key_vault.homelab_key_vault.id
}

resource "azurerm_key_vault_secret" "homelab_container_vaultwarden_db_backup_sas" {
  name         = "vaultwarden-db-backup-sas"
  value        = data.azurerm_storage_account_sas.homelab_container_vaultwarden_db_backup_sas.sas
  key_vault_id = azurerm_key_vault.homelab_key_vault.id
}
