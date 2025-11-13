output "server_ips" {
  value = [for instance in module.servers : instance.vm_ip]
}

output "proxy_ip" {
  value = module.proxy.vm_ip
}
