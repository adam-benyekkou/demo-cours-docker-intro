# budget.tf — budget de consommation mensuel sur le groupe de ressources.
#
# Créé seulement si des adresses de contact sont fournies : Azure refuse un budget
# sans notification. Alerte à 50 % et 90 % (réel), puis 100 % (prévu).
resource "azurerm_consumption_budget_resource_group" "main" {
  # Azure refuse un budget dont les notifications n'ont aucun contact. Définir
  # TF_VAR_budget_contact_emails (ou BUDGET_CONTACT_EMAILS en CI) pour l'activer.
  count = length(var.budget_contact_emails) > 0 ? 1 : 0

  name              = "${var.prefix}-budget"
  resource_group_id = data.azurerm_resource_group.main.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  # Doit tomber le premier jour d'un mois. Ignoré ensuite pour que le budget ne
  # soit jamais recréé simplement parce que la période courante a avancé.
  time_period {
    start_date = "2026-11-01T00:00:00Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 50
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 90
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
