output "web_app_url" {
  value = "https://${azurerm_windows_web_app.site.default_hostname}"
}

output "service_bus_queue" {
  value = azurerm_servicebus_queue.orders.name
}
