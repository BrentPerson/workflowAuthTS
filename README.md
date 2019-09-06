# workflowAuthTS
workflow authentication troubleshooting script
What the Script will do:
	1. WFM Trust
		a. Check and validate the token signing certificate for the WFM trusted security token issuer against the WFM metadata endpoint listed in the trust
			i. It will also check the entire certificate chain if one exists
		b. It will also check each cert in the chain if it exists in the trusted root authority
		c. It will also ask you if you want to attempt to fix the issue by running the timer job "Refresh Security Token Service Metadata Feed"
			i. There is a 20 second sleep after starting the timer job before we check the trust again
			ii. This will loop until the trust is valid or we tell the script we do not want to attempt to fix the issue
	2. User Profiles
		a. This will check for the existence of a user profile(s) based on the SPS-UserPrincipalName
		b. It will display the profile count and ask you if you want to display the profiles
			i. If you say yes it will list each profile object to console otherwise it'll break out of script
	3. Workflow App Only Policy
		a. This will prompt for a web url so we can check if the workflow app only policy feature is activated
			i. If it is activated it will list all the workflow app ID's listed for the web
			ii. If it's not activated it will ask you if you want to try and activate the feature
				1) If you do it will attempt to enable the feature for the web otherwise it'll break out of script
