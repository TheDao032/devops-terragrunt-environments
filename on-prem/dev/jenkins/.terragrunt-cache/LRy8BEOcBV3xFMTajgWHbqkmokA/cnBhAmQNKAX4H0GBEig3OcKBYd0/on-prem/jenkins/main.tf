locals {
  value_file         = "${path.module}/values.yml.tmpl"
  sc_value_file      = "${path.module}/sc.yml.tmpl"
  storage_class_name = "jenkins-disk-rancher"
}

resource "kubectl_manifest" "storage_class" {
  yaml_body = templatefile(local.sc_value_file, {
    storage_class_name = local.storage_class_name
  })
}

resource "helm_release" "main" {
  name             = "jenkins"
  namespace        = "cicd"
  repository       = "https://charts.jenkins.io/"
  version          = var.chart_version
  chart            = "jenkins"
  create_namespace = true
  upgrade_install  = true
  values = (fileexists(local.value_file) ?
    [
      templatefile(
        local.value_file,
        merge(
          var.parameters,
          {
            jenkins_version    = var.jenkins_image_tag,
            storage_class_name = local.storage_class_name
            jenkins_plugins    = var.jenkins_plugins
          },
        )
      )
  ] : null)

  depends_on = [kubectl_manifest.storage_class]
}
