resource "aws_appconfig_application" "app_config" {
  name        = "${local.lvgs_service_strs.kebab}-application"
  description = "${local.lvgs_service_strs.kebab} AppConfig Application"

}

resource "aws_appconfig_environment" "app_config" {
  name           = local.env_str
  description    = "${local.lvgs_service_strs.kebab} AppConfig Environment"
  application_id = aws_appconfig_application.app_config.id

  # monitorという設定項目で、アラーム状態になったらロールバックするように設定もできる
}


# --- Freeform ---
resource "aws_appconfig_configuration_profile" "app_config" {
  application_id = aws_appconfig_application.app_config.id
  description    = "${local.lvgs_service_strs.kebab} Configuration Profile"
  name           = "${local.lvgs_service_strs.kebab}-configuration-profile"

  # デフォルトはAWS.Freeform , AWS.AppConfig.FeatureFlags も選べる
  type = "AWS.Freeform"

  # 設定値をどこに保存するか。今回はAppConfig内に保存するのでhostedとする
  # S3やSSM Parameter Store、Secrets Managerも選択可能
  location_uri = "hosted"

  # 一応ここでLambdaでValidationの設定とかもできる
}


# このリソースを別個で新たに作り、aws_appconfig_deploymentに紐づけるとマネコン側でもバージョン管理できる。
# ただし、この運用にするとどんどん新しいリソース増えてくのと、そもそもIaCしてたらgitでバージョン管理できるので推奨はされないと思う。
resource "aws_appconfig_hosted_configuration_version" "app_config" {
  application_id           = aws_appconfig_application.app_config.id
  configuration_profile_id = aws_appconfig_configuration_profile.app_config.configuration_profile_id
  description              = "${local.lvgs_service_strs.kebab} Freeform Hosted Configuration Version"
  content_type             = "application/json"

  content = jsonencode({
    foo            = "bar",
    fruit          = ["apple", "pear", "orange", "banana"],
    isThingEnabled = true
  })
}

# --- Feature Flag ---
# TODO: マルチバリアント機能フラグの実装
resource "aws_appconfig_configuration_profile" "app_config_ff" {
  application_id = aws_appconfig_application.app_config.id
  description    = "${local.lvgs_service_strs.kebab} Configuration Profile"
  name           = "${local.lvgs_service_strs.kebab}-configuration-profile-feature-flag"

  type         = "AWS.AppConfig.FeatureFlags"
  location_uri = "hosted"
}
resource "aws_appconfig_hosted_configuration_version" "app_config_ff" {
  application_id           = aws_appconfig_application.app_config.id
  configuration_profile_id = aws_appconfig_configuration_profile.app_config_ff.configuration_profile_id
  description              = "${local.lvgs_service_strs.kebab} Feature Flag Configuration Version"
  content_type             = "application/json"

  content = jsonencode({
    flags : {
      foo : {
        name : "foo",
        # この設定をするとShort-Termになるぽい
        _deprecation : {
          "status" : "planned"
        }
      },
      bar : {
        name : "bar",
        # attributesとは何かよくわかってない
        attributes : {
          someAttribute : {
            constraints : {
              type : "string",
              required : true
            }
          },
          someOtherAttribute : {
            constraints : {
              type : "number",
              required : true
            }
          }
        }
      }
    },
    values : {
      foo : {
        enabled : "true",
      },
      bar : {
        enabled : "true",
        someAttribute : "Hello World",
        someOtherAttribute : 123
      }
    },
    # ここの値は固定っぽい
    version : "1"
  })
}

# --- Deployment ---
resource "aws_appconfig_deployment_strategy" "app_config" {
  name                           = "${local.lvgs_service_strs.kebab}-deployment-strategy"
  description                    = "${local.lvgs_service_strs.kebab} Deployment Strategy"
  # たとえば以下の設定だとトータル400分で、25%ずつ開放されるのでつまり100分ごとに開放される、という設定になる。
  # deployment_duration_in_minutes = 400
  # growth_factor                  = 25
  deployment_duration_in_minutes = 0
  growth_factor                  = 100
  growth_type                    = "LINEAR"
  # デプロイ完了した後に、様子見をする時間
  final_bake_time_in_minutes     = 0
  replicate_to                   = "NONE"
}

resource "aws_appconfig_deployment" "app_config" {
  description = "${local.lvgs_service_strs.kebab} deployment"

  application_id         = aws_appconfig_application.app_config.id
  environment_id         = aws_appconfig_environment.app_config.environment_id
  deployment_strategy_id = aws_appconfig_deployment_strategy.app_config.id

  configuration_profile_id = aws_appconfig_configuration_profile.app_config.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.app_config.version_number

}
resource "aws_appconfig_deployment" "app_config_ff" {
  description = "${local.lvgs_service_strs.kebab} deployment"

  application_id         = aws_appconfig_application.app_config.id
  environment_id         = aws_appconfig_environment.app_config.environment_id
  deployment_strategy_id = aws_appconfig_deployment_strategy.app_config.id

  configuration_profile_id = aws_appconfig_configuration_profile.app_config_ff.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.app_config_ff.version_number

}
