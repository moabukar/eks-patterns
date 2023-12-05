output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = <<-EOT
    export KUBECONFIG="/tmp/hup-spoke"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name} --alias ${local.environment}
  EOT
}
