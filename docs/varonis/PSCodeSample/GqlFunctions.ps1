# Set the security protocol to TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-AccessToken {
    param (
        [string]$env,
        [string]$key
    )

    # URL to request the access token
    $url = "https://$env/api/authentication/api_keys/token"

    # Logging the URL for debugging purposes
    Write-Host "Requesting access token from url: $url"

    try {
        # Invoke the REST method to get the access token
        $response = Invoke-RestMethod -Method Post -Uri $url -Headers @{
            "x-api-key" = $key
            "Content-Type" = "application/x-www-form-urlencoded"
        } -Body @{
            "grant_type" = "varonis_custom"
        }

		Write-Host "Access token received"
        # Logging the response for debugging purposes
        if($debug) {Write-Host "$($response.access_token)"}
		
        return $response.access_token
    } catch {
        Write-error "Failed to obtain access token: $_"
        throw "Failed to obtain access token. Please check your environment and API key."
    }
}

function Set-AddNoteToAlerts {param (
        [Parameter(Mandatory = $true)]
        [string[]]$alertIds,

        [Parameter(Mandatory = $true)]
        [string]$note
    )
	Write-Host "Creating add alert note job request"
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }
	$_alertIds = $alertIds -join '","'
    # GraphQL query to create job for adding alert note
    $query = @"
    mutation AddNote {
		  addNoteToAlerts(addNoteToAlertsInput: {  alertIds: ["$_alertIds"], note: "$note" }) {
    succeeded
    extensions {
      errorCode
      errorDetails
      errorMessage
    }
    result {
      id
    }
  }
}
"@
    $body = @{
        query = $query
    } | ConvertTo-Json

    # Logging the query for debugging purposes
    if($debug) {Write-Host "add alert note job request body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to create job for adding alert note
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
        
        return $response
    } catch {
        Write-error "Failed to create job for adding alert note: $_"
        throw "Failed to create job for adding alert note. Please check your GraphQL query and API endpoint."
    }
}

function Set-AlertsStatus {param (
        [Parameter(Mandatory = $true)]
        [string[]]$alertIds
    )
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }
	$_alertIds = $alertIds -join '","'
    # GraphQL query to create job for set alert status
    $query = @"
    mutation SetStatus {
		  setAlertsStatus(setAlertsStatusInput: { alertIds:  ["$_alertIds"], status: UNDER_INVESTIGATION }) {
			succeeded
			extensions {
			  errorCode
			  errorDetails
			  errorMessage
			}
			result {
			  id
			}
		  }
		}
"@
    $body = @{
        query = $query
    } | ConvertTo-Json

    # Logging the query for debugging purposes
    if($debug) {Write-Host "Set alert status request body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to create job for set alert status
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		
        return $response
    } catch {
        Write-error "Failed to create request for set alert status: $_"
        throw "Failed to create request for set alert status. Please check your GraphQL query and API endpoint."
    }
}

function Set-CloseAlerts {param (
        [Parameter(Mandatory = $true)]
        [string[]]$alertIds,

        [Parameter(Mandatory = $true)]
        [int]$closeReason
    )
	

    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }
	$_alertIds = $alertIds -join '","'
    # GraphQL query to create job for close alert
    $query = @"
    mutation closeAlert {
		  closeAlerts(closeAlertsInput: { alertIds: ["$_alertIds"], closingReasonId: $closeReason }) {
			succeeded
			extensions {
			  errorCode
			  errorDetails
			  errorMessage
			}
			result {
			  id
			}
		  }
		}
"@
    $body = @{
        query = $query
    } | ConvertTo-Json

    # Logging the query for debugging purposes
    if($debug) {Write-Host "close alert request body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to create job for close alert
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		
        return $response
    } catch {
        Write-error "Failed to create request for close alert: $_"
        throw "Failed to create request for close alert. Please check your GraphQL query and API endpoint."
    }
}

function Get-AlertsForDateRangeAsync {param (
        [Parameter(Mandatory = $true)]
        [datetime]$fromDate,

        [Parameter(Mandatory = $true)]
        [datetime]$toDate,

        [Parameter(Mandatory = $false)]
        [string]$severity,

		 [Parameter(Mandatory = $false)]
        [string]$status

    )

	$fromDateFormatted = $fromDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $toDateFormatted = $toDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

	# Example usage
	Write-Host "Creating Get Alert job request"
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to create job for get alerts
	$query = @"
query GetAlerts {
    alertsAsync(
        where: {
"@

# Append the severity condition only if $severity has a value
if ($severity) {
    $query += @"
            policy: { severity: { eq: $severity } }
"@
}

if ($status) {
    $query += @"
            status: { eq: $status }
"@
}

$query += @"
            generationTime: {
                between: {
                    from: "$fromDateFormatted",
                    to: "$toDateFormatted"
                }
            }
        }
    ) {
        jobId
        jobProgress
        jobStatus
        results {
            escalationType
            eventsCount
            hasSensitiveResource
            hasTaggedResource
            id
            isAssignedToVaronis
            status
            closedBy {
                name
            }
            closeReason {
                id
                name
            }
            dataSource {
                id
                name
                type
            }
            generationTime {
                dateTimeUtc
            }
            note {
                content
                createdBy {
                    name
                }
                createTime {
                    dateTimeUtc
                }
            }
            policy {
                category
                id
                name
                severity
            }
        }
    }
}
"@

	
    $body = @{
        query = $query
    } | ConvertTo-Json

    # Logging the query for debugging purposes
    if($debug) {Write-Host "Get alerts job request body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to create job for get alerts
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		Write-Host "Get Alert job created"
        # Logging the response for debugging purposes
        if($debug) {Write-Host "Create Get Alert job reponse: `n $($response | ConvertTo-Json -Depth 10)"}
		
        return $response
    } catch {
        Write-error "Failed to create job for get alerts: `n$_"
        throw "Failed to create job for get alerts. Please check your GraphQL query and API endpoint."
    }
}

function Get-AlertsForLastDaysAsync {param (
        [Parameter(Mandatory = $true)]
        [int]$lastDays
    )

	# Example usage
	Write-Host "Creating Get Alert job request"
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to create job for get alerts
    $query = @"
    query GetAlerts {
                      alertsAsync(
						where: {
						  status: { eq: NEW },
						  generationTime: {lastdays: $lastDays }
						}
					  ) {
						jobId
						jobProgress
						jobStatus
						results {
						  escalationType
						  eventsCount
						  hasSensitiveResource
						  hasTaggedResource
						  id
						  isAssignedToVaronis
						  status
						  closedBy {
							name
						  }
						  closeReason {
							id
							name
						  }
						  dataSource {
							id
							name
							type
						  }
						  generationTime {
							dateTimeUtc
						  }
						  note {
							content
							createdBy {
							  name
							}
							createTime {
							  dateTimeUtc
							}
						  }
						  policy {
							category
							id
							name
							severity
						  }
						}
					  }
					}
"@
    $body = @{
        query = $query
    } | ConvertTo-Json

    # Logging the query for debugging purposes
    if($debug) {Write-Host "Get alerts job request body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to create job for get alerts
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		Write-Host "Get Alert job created"
        # Logging the response for debugging purposes
        if($debug) {Write-Host "Create Get Alert job reponse: `n $($response | ConvertTo-Json -Depth 10)"}
		
        return $response
    } catch {
        Write-error "Failed to create job for get alerts: `n$_"
        throw "Failed to create job for get alerts. Please check your GraphQL query and API endpoint."
    }
}

function Get-AlertsQueryJob {param (
        [string]$jobId
    )
	Write-Host "Querying Get Alert job result"
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to get alerts from requested job
    $query = @"
    query GetAlertsResults {
				  alertsQueryJob(jobId: "$jobId") {
					jobId
					jobProgress
					jobStatus
					results {
					  escalationType
					  eventsCount
					  hasSensitiveResource
					  hasTaggedResource
					  id
					  isAssignedToVaronis
					  status
					  closedBy {
						name
					  }
					  closeReason {
						id
						name
					  }
					  dataSource {
						id
						name
						type
					  }
					  generationTime {
						dateTimeUtc
					  }
					  note {
						content
						createdBy {
						  name
						}
						createTime {
						  dateTimeUtc
						}
					  }
					  policy {
						category
						id
						name
						severity
					  }
					}
				  }
				}
"@
    $body = @{
        query = $query
    } | ConvertTo-Json -Depth 10
	
    # Logging the query for debugging purposes
    if($debug) {Write-Host "Querying get alerts job with body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to get alert job results
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		Write-Host "Get Alert job result completed. job status $($response.data.AlertsAsyncQueryJob.jobStatus)"
		# Logging the response for debugging purposes
		if($debug) {Write-Host "Get Alert job result: `n  $($response | ConvertTo-Json -Depth 10)"}
		
        return $response
    } catch {
        Write-error "Failed to query get alert job: `n$_"
        throw "Failed to query get alert job. Please check your GraphQL query and API endpoint."
    }
}

function Get-AlertedEventsAsync {param (
        [Parameter(Mandatory = $true)]
        [string[]]$alertId
    )
	Write-Host "Creating get alerted events job request"
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }
	$alertId = $ids -join '","'
    # GraphQL query to create job for get alerted events
    $query = @"
    query GetAlertedEvents {
      alertedEventsAsync(where: { alert: { id: { in: ["$alertId"] } } }) {
        jobId
        jobProgress
        jobStatus
        results {
          affectedObjectName
          agentVersion
          app
          applicationProtocol
          clientIP
          clientType
          collectionMethod
          connectionType
          correlationID
          count
          description
          direction
          dnsFlag
          dnsRecordType
          downloadSizeinBytes
          endTime
          httpMethod
          id
          impersonationLevel
          infoTags
          ingestionDateTime
          isAlerted
          logonType
          operation
          originalEventName
          protocol
          sessionDuration
          sourcePort
          sourceZone
          status
          statusReason
          statusReasonCode
          transportLayer
          uploadSizeInBytes
          actor {
            affiliation
            applicationID
            applicationPublisher
            department
            distinguishedName
            email
            expirationDate
            expirationStatus
            id
            isDisabled
            isLockedOut
            isMailboxOwner
            isStale
            isVerifiedPublisher
            lastLogonTime
            name
            note
            passwordExpirationStatus
            privilegedIdentityType
            samAccountName
            type
            userPrincipalName
            vpnGroup
            directoryServices {
              name
            }
            dnsDomain {
              name
            }
            entraIDRole {
              name
            }
            manager {
              name
            }
            tags {
              name
            }
          }
          affectedIdentity {
            affiliation
            applicationID
            applicationPublisher
            department
            email
            expirationDate
            expirationStatus
            id
            isDisabled
            isLockedOut
            isStale
            isVerifiedPublisher
            lastLogonTime
            name
            note
            passwordExpirationStatus
            privilegedIdentityType
            samAccountName
            type
            userPrincipalName
            directoryServices {
              name
            }
            dnsDomain {
              name
            }
            entraIDRole {
              name
            }
            manager {
              name
            }
            tags {
              name
            }
          }
          affectedResource {
            accessDate
            creationDate
            entityIdx
            exposureLevel
            fileCount
            id
            isSensitive
            localMappedPath
            mailItemType
            modifyDate
            numberOfFilesInSubFolders
            numberOfNestedFiles
            numberOfNestedFolders
            path
            pathDepth
            physicalSizeOfFolderInBytes
            physicalSizeOfSubfoldersInBytes
            sharePath
            sizeOfFolderandSubfoldersInBytes
            sizeOfFolderInBytes
            sizeOfSubfoldersInBytes
            sizePhysicalSDTFileInBytes
            totalNumberOfNestedObjects
            type
            classification {
              category
              recordCountPerCategory
              recordCountPerRuleDirect
              recordCountPerRuleSubDir
              results
              totalRecordCount
            }
            classificationLabels {
              results
              directLabel {
                name
              }
              nestedLabel {
                name
              }
            }
            mail {
              attachmentName
              deliveryTime
              isSentOutsidetheOrganization
              messageSubject
              representing
              source
              withAttachments
              headers {
                messageOriginalSender
                messageReceivedServerIP
                messageSentDate
                authenticationResults {
                  dkim {
                    passed
                  }
                  dmarc {
                    passed
                  }
                  spf {
                    passed
                  }
                }
              }
              mailRecipient {
                name
              }
              sender {
                name
              }
            }
            mailbox {
              type
            }
            parent {
              id
            }
            resourceOwner {
              name
            }
            volume {
              id
              name
            }
            file {
              fileType
            }
          }
          alert {
            id
            generationTime {
              dateTimeUtc
            }
            policy {
              category
              id
              name
              severity
            }
          }
          authentication {
            package
            preAuthenticationType
            protocol
            ticketEncryptionType
            ticketOption
          }
          changedPermission {
            isDirectChange
            permissionFlag {
              name
            }
          }
          collectionDevice {
            hostname
          }
          dataSource {
            id
            name
            type
          }
          destination {
            deviceName
            domainName
            ip
            port
            zone
            url {
              address
              categorization
              reputation
            }
          }
          device {
            hostName
            managedStatus
            operatingSystem
            trustType
            userAgent
            externalIP {
              ip
              isMalicious
              reputation
              threatType
            }
          }
          externalActivity {
            rawLog
          }
          generationTime {
            dateTimeUtc
            dayOfWeek
            hour
          }
          impersonation {
            affiliation
            applicationID
            name
            privilegedIdentityType
            type
            tags {
              id
              name
            }
          }
          location {
            country
            isDeniedLocation
            state
          }
          name {
            eventName
          }
          nat {
            destination {
              address
              port
            }
            source {
              address
              port
            }
          }
          networkDevice {
            networkPolicy {
              name
            }
          }
          onAzureAdRoleGroup {
            assignedRoles
            endTime
            startTime
          }
          onGPO {
            configurationType
            updatedGPOVersionNumber
            settings {
              name
              path
              valueAfterChange
              valueBeforeChange
            }
          }
          query {
            filter
            requiredAttributes
            scope
          }
          session {
            browserType
            id
            sessionID
            azureAuthentication {
              authenticationMethod
              authenticationMethodDetails
              authenticationRequirement
              authenticationResultDetail
              authenticationStep
              conditionalAccessStatus
              reasonDetails
              status
              tokenIssuerType
            }
            token {
              protectionStatus
              uniqueIdentifier
            }
          }
          trustee {
            affiliation
            applicationID
            applicationPublisher
            isVerifiedPublisher
            name
            privilegedIdentityType
            type
            dnsDomain {
              name
            }
          }
          violation {
            policy {
              categoryType
            }
          }
        }
      }
    }
"@
    $body = @{
        query = $query
    } | ConvertTo-Json

    # Logging the query for debugging purposes
    if($debug) {Write-Host "get alerted events job request body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to create job for get alerted events
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		Write-Host "get alerted events job created"
        # Logging the response for debugging purposes
        if($debug) {Write-Host "Create get alerted events job reponse: `n $($response | ConvertTo-Json -Depth 10)"}
		
        return $response
    } catch {
        Write-error "Failed to create job for get alerted events: $_"
        throw "Failed to create job for get alerted events. Please check your GraphQL query and API endpoint."
    }
}

function Get-AlertedEventsQueryJob {param (
        [string]$jobId
    )
	Write-Host "Querying get alerted events job result"
    # URL for the GraphQL API
    $url = "https://$env/api/graphql" #todo remove alert from url
    $headers = @{
        "Authorization" = "Bearer $global:token"
        "Content-Type" = "application/json"
    }

    # GraphQL query to get alerted events from requested job
    $query = @"
    query GetAlertedEventsResults {
			  alertedEventsQueryJob(jobId: "$jobId") {
				jobId
				jobProgress
				jobStatus
				results {
                  affectedObjectName
                  agentVersion
                  app
                  applicationProtocol
                  clientIP
                  clientType
                  collectionMethod
                  connectionType
                  correlationID
                  count
                  description
                  direction
                  dnsFlag
                  dnsRecordType
                  downloadSizeinBytes
                  endTime
                  httpMethod
                  id
                  impersonationLevel
                  infoTags
                  ingestionDateTime
                  isAlerted
                  logonType
                  operation
                  originalEventName
                  protocol
                  sessionDuration
                  sourcePort
                  sourceZone
                  status
                  statusReason
                  statusReasonCode
                  transportLayer
                  uploadSizeInBytes
                  actor {
                    affiliation
                    applicationID
                    applicationPublisher
                    department
                    distinguishedName
                    email
                    expirationDate
                    expirationStatus
                    id
                    isDisabled
                    isLockedOut
                    isMailboxOwner
                    isStale
                    isVerifiedPublisher
                    lastLogonTime
                    name
                    note
                    passwordExpirationStatus
                    privilegedIdentityType
                    samAccountName
                    type
                    userPrincipalName
                    vpnGroup
                    directoryServices {
                      name
                    }
                    dnsDomain {
                      name
                    }
                    entraIDRole {
                      name
                    }
                    manager {
                      name
                    }
                    tags {
                      name
                    }
                  }
                  affectedIdentity {
                    affiliation
                    applicationID
                    applicationPublisher
                    department
                    email
                    expirationDate
                    expirationStatus
                    id
                    isDisabled
                    isLockedOut
                    isStale
                    isVerifiedPublisher
                    lastLogonTime
                    name
                    note
                    passwordExpirationStatus
                    privilegedIdentityType
                    samAccountName
                    type
                    userPrincipalName
                    directoryServices {
                      name
                    }
                    dnsDomain {
                      name
                    }
                    entraIDRole {
                      name
                    }
                    manager {
                      name
                    }
                    tags {
                      name
                    }
                  }
                  affectedResource {
                    accessDate
                    creationDate
                    entityIdx
                    exposureLevel
                    fileCount
                    id
                    isSensitive
                    localMappedPath
                    mailItemType
                    modifyDate
                    numberOfFilesInSubFolders
                    numberOfNestedFiles
                    numberOfNestedFolders
                    path
                    pathDepth
                    physicalSizeOfFolderInBytes
                    physicalSizeOfSubfoldersInBytes
                    sharePath
                    sizeOfFolderandSubfoldersInBytes
                    sizeOfFolderInBytes
                    sizeOfSubfoldersInBytes
                    sizePhysicalSDTFileInBytes
                    totalNumberOfNestedObjects
                    type
                    classification {
                      category
                      recordCountPerCategory
                      recordCountPerRuleDirect
                      recordCountPerRuleSubDir
                      results
                      totalRecordCount
                    }
                    classificationLabels {
                      results
                      directLabel {
                        name
                      }
                      nestedLabel {
                        name
                      }
                    }
                    mail {
                      attachmentName
                      deliveryTime
                      isSentOutsidetheOrganization
                      messageSubject
                      representing
                      source
                      withAttachments
                      headers {
                        messageOriginalSender
                        messageReceivedServerIP
                        messageSentDate
                        authenticationResults {
                          dkim {
                            passed
                          }
                          dmarc {
                            passed
                          }
                          spf {
                            passed
                          }
                        }
                      }
                      mailRecipient {
                        name
                      }
                      sender {
                        name
                      }
                    }
                    mailbox {
                      type
                    }
                    parent {
                      id
                    }
                    resourceOwner {
                      name
                    }
                    volume {
                      id
                      name
                    }
                    file {
                      fileType
                    }
                  }
                  alert {
                    id
                    generationTime {
                      dateTimeUtc
                    }
                    policy {
                      category
                      id
                      name
                      severity
                    }
                  }
                  authentication {
                    package
                    preAuthenticationType
                    protocol
                    ticketEncryptionType
                    ticketOption
                  }
                  changedPermission {
                    isDirectChange
                    permissionFlag {
                      name
                    }
                  }
                  collectionDevice {
                    hostname
                  }
                  dataSource {
                    id
                    name
                    type
                  }
                  destination {
                    deviceName
                    domainName
                    ip
                    port
                    zone
                    url {
                      address
                      categorization
                      reputation
                    }
                  }
                  device {
                    hostName
                    managedStatus
                    operatingSystem
                    trustType
                    userAgent
                    externalIP {
                      ip
                      isMalicious
                      reputation
                      threatType
                    }
                  }
                  externalActivity {
                    rawLog
                  }
                  generationTime {
                    dateTimeUtc
                    dayOfWeek
                    hour
                  }
                  impersonation {
                    affiliation
                    applicationID
                    name
                    privilegedIdentityType
                    type
                    tags {
                      id
                      name
                    }
                  }
                  location {
                    country
                    isDeniedLocation
                    state
                  }
                  name {
                    eventName
                  }
                  nat {
                    destination {
                      address
                      port
                    }
                    source {
                      address
                      port
                    }
                  }
                  networkDevice {
                    networkPolicy {
                      name
                    }
                  }
                  onAzureAdRoleGroup {
                    assignedRoles
                    endTime
                    startTime
                  }
                  onGPO {
                    configurationType
                    updatedGPOVersionNumber
                    settings {
                      name
                      path
                      valueAfterChange
                      valueBeforeChange
                    }
                  }
                  query {
                    filter
                    requiredAttributes
                    scope
                  }
                  session {
                    browserType
                    id
                    sessionID
                    azureAuthentication {
                      authenticationMethod
                      authenticationMethodDetails
                      authenticationRequirement
                      authenticationResultDetail
                      authenticationStep
                      conditionalAccessStatus
                      reasonDetails
                      status
                      tokenIssuerType
                    }
                    token {
                      protectionStatus
                      uniqueIdentifier
                    }
                  }
                  trustee {
                    affiliation
                    applicationID
                    applicationPublisher
                    isVerifiedPublisher
                    name
                    privilegedIdentityType
                    type
                    dnsDomain {
                      name
                    }
                  }
                  violation {
                    policy {
                      categoryType
                    }
                  }
                }
              }
            }
"@
    $body = @{
        query = $query
    } | ConvertTo-Json -Depth 10
	
    # Logging the query for debugging purposes
    if($debug) {Write-Host "Querying get alerted events job with body: `n $($($body -replace '\\r\\n', "`n") -replace "\\t", "    ")"}

    try {
        # Invoke the REST method to get alerted events job results
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
		if ($response.errors -ne $null)
		{
			throw "$($response | ConvertTo-Json -Depth 10)"
		}
		Write-Host "get alerted events job result completed. job status $($response.data.alertedEventsQueryJob.jobStatus)"
		# Logging the response for debugging purposes
		if($debug) {Write-Host "get alerted events job result: `n  $($response | ConvertTo-Json -Depth 10)"}
		
        return $response
    } catch {
        Write-error "Failed to query get alerted events job: `n$_"
        throw "Failed to query get alerted events job. Please check your GraphQL query and API endpoint."
    }
}
