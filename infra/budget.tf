resource "azurerm_consumption_budget_resource_group" "main" {
  # Azure refuses a budget whose notifications have no contact. Set
  # TF_VAR_budget_contact_emails (or BUDGET_CONTACT_EMAILS in CI) to enable it.
  count = length(var.budget_contact_emails) > 0 ? 1 : 0

  name              = "${local.prefix}-budget"
  resource_group_id = data.azurerm_resource_group.main.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  # Must fall on the first day of a month. Ignored afterwards so the budget is
  # never recreated just because the current period moved on.
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
