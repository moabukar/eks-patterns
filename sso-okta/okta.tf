# You can generate an Okta API token in the Okta Developer Console. Follow these instructions: https://bit.ly/get-okta-api-token

provider "okta" {
  org_name  = "dev-<ORG_ID>"
  base_url  = "okta.com"
  api_token = "<OKTA_APU_TOKEN>"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

resource "okta_user" "admin" {
  for_each = { for admin in var.admin_user_config : admin.email => admin }

  first_name = each.value.first_name
  last_name  = each.value.last_name
  login      = each.value.email
  email      = each.value.email
}

resource "okta_user" "user" {
  for_each = { for user in var.user_config : user.email => user }

  first_name = each.value.first_name
  last_name  = each.value.last_name
  login      = each.value.email
  email      = each.value.email
}

resource "okta_group" "operators" {
  name        = "eks-operators"
  description = "EKS Platform Operators"
}

resource "okta_group" "developers" {
  name        = "eks-developers"
  description = "EKS Platform Developers"
}

resource "okta_group_memberships" "operators" {
  for_each = { for admin in var.admin_user_config : admin.email => admin }

  group_id = okta_group.operators.id
  users = [
    okta_user.admin[each.key].id
  ]
}

resource "okta_group_memberships" "developers" {
  for_each = { for user in var.user_config : user.email => user }

  group_id = okta_group.developers.id
  users = [
    okta_user.user[each.key].id
  ]
}

resource "okta_app_oauth" "eks" {
  label                      = "eks"
  type                       = "native"
  grant_types                = ["authorization_code"]
  redirect_uris              = ["http://localhost:8000"]
  post_logout_redirect_uris  = ["http://localhost:8000"]
  token_endpoint_auth_method = "none"
  response_types             = ["code"]
  issuer_mode                = "DYNAMIC"
  pkce_required              = true
  groups_claim {
    name        = "groups"
    type        = "FILTER"
    filter_type = "STARTS_WITH"
    value       = "eks-"
  }
}

resource "okta_app_group_assignments" "eks" {
  app_id = okta_app_oauth.eks.id
  group {
    id = okta_group.operators.id
  }
  group {
    id = okta_group.developers.id
  }
}

resource "okta_auth_server" "eks" {
  name        = "EKS"
  audiences   = ["http://localhost:8000"]
  description = "EKS Auth Server"
  issuer_mode = "ORG_URL"
  status      = "ACTIVE"
}

resource "okta_auth_server_claim" "eks_groups" {
  name                    = "groups"
  auth_server_id          = okta_auth_server.eks.id
  always_include_in_token = true
  claim_type              = "IDENTITY"
  value_type              = "GROUPS"
  group_filter_type       = "STARTS_WITH"
  value                   = "eks-"
}

resource "okta_auth_server_policy" "eks" {
  name             = "eks"
  auth_server_id   = okta_auth_server.eks.id
  description      = "EKS"
  status           = "ACTIVE"
  priority         = 1
  client_whitelist = [okta_app_oauth.eks.id]
}

resource "okta_auth_server_policy_rule" "auth_code" {
  name                 = "EKS AuthCode + PKCE"
  auth_server_id       = okta_auth_server.eks.id
  policy_id            = okta_auth_server_policy.eks.id
  status               = "ACTIVE"
  priority             = 1
  grant_type_whitelist = ["authorization_code"]
  group_whitelist      = [okta_group.operators.id, okta_group.developers.id]
  scope_whitelist      = ["*"]
}

resource "kubernetes_cluster_role_binding_v1" "cluster_admin" {
  metadata {
    name = "oidc-cluster-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "Group"
    name      = "eks-operators"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_cluster_role_binding_v1" "cluster_viewer" {
  metadata {
    name = "oidc-cluster-viewer"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }
  subject {
    kind      = "Group"
    name      = "eks-developers"
    api_group = "rbac.authorization.k8s.io"
  }
}
