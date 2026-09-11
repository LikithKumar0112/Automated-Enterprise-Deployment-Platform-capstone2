// Shared step: consistent Slack notification format for deploy pipelines.
// Usage: notifySlack(status: 'success', environment: params.ENVIRONMENT)
def call(Map config) {
    def color = config.status == 'success' ? 'good' : 'danger'
    def icon = config.status == 'success' ? '✅' : '❌'
    def channel = config.status == 'success' ? '#deployments' : '#deployments-alerts'

    slackSend(
        channel: channel,
        color: color,
        message: "${icon} Deployment ${config.status}: ${env.JOB_NAME} #${env.BUILD_NUMBER} to ${config.environment}"
    )
}
