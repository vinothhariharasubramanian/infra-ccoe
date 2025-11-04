# ARM Templates

This directory contains Azure Resource Manager (ARM) template for Logic Apps
## Templates

### logic-apps.json
Deploys Azure Logic Apps for automated patch management using Azure Update Manager.

**Components:**
- **Pre-maintenance Logic App**: Triggered by maintenance events, creates VM OS disk snapshots, enables monitoring
- **Post-maintenance Logic App**: Sends completion notifications with patch results
- **Maintenance Monitor**: Monitors for patch failures and sends alerts
- **Scheduler**: Coordinates monitoring during maintenance windows
- **On-demand Pre-maintenance**: Manual trigger for ad-hoc patching [**NOT USED**]

**Parameters:**
- `ResourceGroupName`: Target resource group name
- `EnvironmentStage`: Environment (prod/ppd)
- `TeamsWebhookUrl`: Teams webhook for notifications

**Features:**
- Automated VM snapshot creation [ **Pre Maintenance Phase** ]
- Teams notifications for maintenance events [ **Pre Maintenance Phase** ]
- Patch failure monitoring and alerting [ **Maintenance Phase** ]
- Resource Graph queries for patch monitoring [ **Maintenance Phase** ]
- Final Report on Patch status [ **Post Maintenance Phase** ]