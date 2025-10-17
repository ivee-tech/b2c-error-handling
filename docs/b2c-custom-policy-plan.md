# Azure AD B2C Custom Policy Development Plan
## Contoso Transit - Identity Modernization Initiative

**Date:** October 12, 2025  
**Project:** Identity Modernization Initiative  
**Support Cases (Sanitized):**
- CT-CASE-001 - Retry/timeout on CRM contact creation
- CT-CASE-002 - B2C page when an API error occurs

---

## 1. Executive Summary

This plan addresses the development of custom Azure AD B2C policies for Contoso Transit's identity modernization, focusing on:
- **Retry and timeout handling** for CRM API calls
- **Error capturing and user experience** improvements
- **Race condition mitigation** during user creation
- **Integration with Dynamics CRM** deduplication plugins

### Key Challenges Identified
1. B2C automatically retries POST requests when CRM API calls approach 10-second timeout
2. Duplicate user creation attempts causing race conditions in CRM and IDM
3. Error messages not displaying properly on custom policy UI banner
4. Users being redirected to Contoso Transit website without error context (poor UX)
5. CRM plugin delays (deduplication logic) exacerbating B2C retry behavior

---

## 2. Policy Architecture Overview

### 2.1 Policy Structure
The custom policy will be built on the **Identity Experience Framework (IEF)** with the following layers:

**Base Policies (LocalAccounts set – see `policies/LocalAccounts/`):**
- `TrustFrameworkBase.xml` – Core framework definitions
- `TrustFrameworkLocalization.xml` – Error messages and UI strings
- `TrustFrameworkExtensions.xml` – Custom extensions and integrations (REST user validation, error page override)

**Relying Party Policies (LocalAccounts):**
- `SignUpOrSignin.xml` – User journey orchestration (PolicyId: `B2C_1A_signup_signin`)
- `ProfileEdit.xml` – Profile management (optional)
- `PasswordReset.xml` – Password reset flow (optional)

### 2.2 Integration Points
- **CRM API** - Contact creation and deduplication
- **IDM System** - User profile management
- **Legacy ADFS/AD** - Password validation (6-month overlap period)
- **Application Insights** - Telemetry and error tracking

---

## 3. Error Handling Strategy

### 3.1 Timeout and Retry Configuration

**Objective:** Prevent B2C from automatically retrying CRM API calls

**Approach:**
1. **REST API Technical Profile Configuration**
   - Set explicit timeout values (extend beyond 10 seconds)
   - Configure `SendClaimsIn` and error handling metadata
   - Implement circuit breaker pattern at API layer

2. **Timeout Settings to Implement:**
   - `ServiceConfiguration/Timeout`: 30 seconds (or higher based on CRM plugin SLA)
   - `ServiceConfiguration/MaxRetries`: 0 (disable automatic retries)
   - Implement custom retry logic at application layer if needed

3. **CRM API Wrapper Considerations:**
   - Add idempotency keys to prevent duplicate operations
   - Implement server-side deduplication using unique identifiers
   - Return appropriate HTTP status codes (200, 409 Conflict, 503 Service Unavailable)

### 3.2 Error Response Handling

**Current Problem:** Errors not displayed on UI banner, users redirected without context

**Solution Components:**

1. **HTTP Status Code Mapping**
   - **200 OK with error payload** - For user-actionable errors that should display on UI
   - **409 Conflict** - User already exists (handle gracefully)
   - **429 Too Many Requests** - Throttling (queue and retry)
   - **500/503** - Server errors (display generic message, log details)

2. **Error Response Structure (from CRM API)**
   ```
   HTTP 200 OK
   {
     "status": "error",
     "errorCode": "DUPLICATE_USER",
     "userMessage": "An account with this email already exists.",
     "technicalDetails": "CRM Contact ID collision detected",
     "correlationId": "..."
   }
   ```

3. **Technical Profile Error Handling Metadata**
   - Configure `RaiseErrorIfClaimsPrincipalDoesNotExist`
   - Map error codes to localized user messages
   - Implement fallback error display logic

### 3.3 Race Condition Mitigation

**Objective:** Prevent duplicate user creation when B2C retries overlap with CRM deduplication

**Strategy:**

1. **Pre-Creation Validation Step**
   - Add orchestration step to check user existence before CRM call
   - Query IDM/B2C directory first
   - Short-circuit if user already exists

2. **Idempotency Token Implementation**
   - Generate unique token at journey start (GUID)
   - Pass token to CRM API with creation request
   - CRM validates token and rejects duplicates within time window

3. **Optimistic Locking Pattern**
   - Use version numbers or timestamps
   - CRM plugin checks for concurrent modifications
   - Return 409 Conflict if race detected

4. **Transaction Coordination**
   - Implement distributed transaction pattern if possible
   - Or use eventual consistency with compensating transactions

---

## 4. Custom Policy Components

### 4.1 Claims Schema Design

**Input Claims:**
- User registration data (email, name, phone, etc.)
- Business-specific attributes for IDM
- Idempotency token
- Correlation ID for tracking

**Output Claims:**
- B2C Object ID
- CRM Contact ID
- IDM User ID
- Error details (for logging)

**Transformation Claims:**
- Normalized email
- Validation flags
- Retry attempt counter

### 4.2 Technical Profiles

**Profile 1: CRM-Contact-Creation**
- Type: `REST`
- Purpose: Create contact in Dynamics CRM
- Timeout: 30 seconds
- Retries: Disabled
- Error handling: Map to user-friendly messages
- Include metadata for idempotency

**Profile 2: IDM-User-Validation**
- Type: `REST`
- Purpose: Check if user exists in IDM before creation
- Timeout: 5 seconds
- Fast-fail on errors

**Profile 3: LDAP-Password-Validation** (for migration period)
- Type: `REST` (wrapping LDAP call)
- Purpose: Validate legacy passwords
- Timeout: 10 seconds
- Update B2C password hash on success

**Profile 4: Error-Handler**
- Type: `SelfAsserted`
- Purpose: Display structured errors to users
- Preconditions: Error claim exists
- Metadata: Configure custom error page

**Profile 5: Application-Insights-Logger**
- Type: `ApplicationInsights`
- Purpose: Log all events and errors
- Include correlation ID, user context, API response times

### 4.3 User Journey Orchestration

**Orchestration Steps for Sign-Up:**

1. **User Input Collection** (Step 1)
   - Type: `ClaimsExchange`
   - Technical Profile: `LocalAccountSignUpWithLogonEmail`
   - Generate idempotency token and correlation ID

2. **Pre-Validation Check** (Step 2)
   - Type: `ClaimsExchange`
   - Technical Profile: `IDM-User-Validation`
   - Precondition: Check if email already registered
   - Error handling: Display user-friendly message if exists

3. **CRM Contact Creation** (Step 3)
   - Type: `ClaimsExchange`
   - Technical Profile: `CRM-Contact-Creation`
   - Include idempotency token
   - On success: Proceed to next step
   - On error: Go to error handler (Step 6)

4. **B2C User Creation** (Step 4)
   - Type: `ClaimsExchange`
   - Technical Profile: `AAD-UserWriteUsingLogonEmail`
   - Only execute if Step 3 succeeds
   - Store CRM Contact ID in extension attribute

5. **Success Confirmation** (Step 5)
   - Type: `SendClaims`
   - Issue token with user claims

6. **Error Display** (Step 6 - Conditional)
   - Type: `ClaimsExchange`
   - Technical Profile: `Error-Handler`
   - Precondition: Error claim populated
   - Display structured error message
   - Option to retry or contact support

### 4.4 Error Message Localization

**English Messages:**
- `error.crm.timeout`: "We're experiencing high demand. Please try again in a few moments."
- `error.crm.duplicate`: "An account with this email already exists. Please sign in instead."
- `error.crm.unavailable`: "Our systems are temporarily unavailable. Please try again later."
- `error.general`: "Something went wrong. Please contact support with reference: {correlationId}"

**Configure in ContentDefinitions:**
- Custom HTML/CSS for error banner
- Inline error display (not redirect)
- Support ticket link with pre-filled correlation ID

---

## 5. CRM Integration Considerations

### 5.1 CRM Plugin Performance

**Current State:**
- CRM plugins run inline for deduplication
- Delays observed on CRM side (not app service)
- App Insights shows quick app service responses, long CRM waits

**Recommendations for CRM Team:**

1. **Plugin Optimization**
   - Profile deduplication queries (indexes, query plans)
   - Consider async plugin execution for non-critical operations
   - Implement plugin timeout limits

2. **Caching Strategy**
   - Cache recent deduplication checks (5-minute TTL)
   - Reduce database round-trips

3. **Database Performance**
   - Review indexes on contact lookup fields
   - Optimize contact deduplication stored procedures

### 5.2 API Design Patterns

**Idempotency Implementation:**
```
Header: X-Idempotency-Key: {GUID}
CRM stores key + timestamp for 15 minutes
Duplicate requests with same key return original response
```

**Response Contract:**
```
Success (200):
{
  "contactId": "...",
  "status": "created|existing",
  "idempotencyKey": "..."
}

Error (200 with error payload):
{
  "status": "error",
  "errorCode": "DUPLICATE|TIMEOUT|VALIDATION_ERROR",
  "userMessage": "...",
  "technicalDetails": "...",
  "retryAfter": 30 (optional, in seconds)
}
```

---

## 6. Monitoring and Observability

### 6.1 Application Insights Integration

**Events to Track:**
- User journey start/completion
- Each orchestration step execution time
- CRM API call duration and response codes
- Error occurrences with full context
- Retry attempts (if implemented)

**Custom Dimensions:**
- `correlationId`
- `userId` (obfuscated)
- `journey` (sign-up, sign-in, etc.)
- `step` (orchestration step number)
- `apiEndpoint`
- `crmContactId`

**Metrics to Monitor:**
- CRM API P95/P99 latency
- Error rate by type
- User journey completion rate
- Retry frequency

### 6.2 Alerting Strategy

**Critical Alerts:**
- CRM API error rate > 5% (5-minute window)
- CRM API P95 latency > 25 seconds
- User journey failure rate > 10%

**Warning Alerts:**
- CRM API P95 latency > 15 seconds
- Increased retry attempts
- Specific error codes spiking

### 6.3 Dashboards

**Real-Time Operations Dashboard:**
- Current CRM API health
- Active user journeys
- Error rate trends
- API response time distribution

**Migration Progress Dashboard:**
- Users migrated per hour
- Success/failure ratio
- Bottleneck identification
- Estimated completion time

---

## 7. Testing Strategy

### 7.1 Unit Testing (Custom Policy XML)

**Validation Checks:**
- Schema validation against B2C XSD
- All TechnicalProfile references exist
- Claims mappings are complete
- Preconditions logic is sound
- Error handling paths are defined

**Tools:**
- XML validators
- B2C policy tester (IEF debugger)
- Custom PowerShell validation scripts

### 7.2 Integration Testing

**Test Scenarios:**

1. **Happy Path**
   - New user sign-up
   - CRM contact created successfully
   - B2C user created successfully
   - Token issued

2. **CRM Timeout Scenario**
   - Mock CRM API with 15-second delay
   - Verify B2C waits without retry
   - Verify timeout error displayed correctly
   - Verify user not created in B2C

3. **Duplicate User Scenario**
   - Attempt to create user with existing email
   - Verify pre-validation catches it
   - Verify user-friendly error message
   - Verify no CRM call made (short-circuit)

4. **Race Condition Simulation**
   - Send 2 concurrent sign-up requests with same email
   - Verify idempotency key prevents duplicate
   - Verify only one user created
   - Verify second request gets appropriate response

5. **CRM Plugin Delay Scenario**
   - CRM responds in 8-10 seconds (near timeout)
   - Verify no automatic retry from B2C
   - Verify successful creation despite delay

6. **Error Display Test**
   - Trigger various error codes
   - Verify errors display on UI banner (not redirect)
   - Verify correlation IDs in error messages
   - Verify user can retry from error page

### 7.3 Load Testing

**Migration Weekend Simulation:**
- Test with batches matching production plan (6,000 users per 5 minutes)
- Monitor CRM API performance under load
- Verify error handling under stress
- Measure end-to-end latency

**Scenarios:**
- 100 concurrent sign-ups
- 500 concurrent sign-ups
- Mixed operations (sign-up, sign-in, profile edit)

**Success Criteria:**
- 99% success rate
- P95 latency < 15 seconds
- No duplicate user creation
- All errors properly displayed

### 7.4 User Acceptance Testing (UAT)

**Test with Contoso Transit Business Users:**
- Walk through sign-up flow
- Intentionally trigger errors
- Verify error messages are clear
- Verify retry functionality works
- Collect UX feedback

---

## 8. Deployment Strategy

### 8.1 Environment Strategy

**Environments:**
1. **Development** - Initial policy development and unit testing
2. **Test** - Integration testing with mock CRM/IDM
3. **Staging** - Full integration with production-like CRM/IDM
4. **Production** - Live migration environment

### 8.2 Phased Rollout

**Phase 1: Policy Development (Week 1)**
- Create base and extension policies
- Configure CRM REST API technical profiles
- Implement error handling logic
- Unit test in development B2C tenant

**Phase 2: Integration Testing (Week 2)**
- Deploy to test environment
- Integration testing with CRM and IDM
- Performance testing with small batches
- Fix identified issues

**Phase 3: Staging Validation (Week 3)**
- Deploy to staging with production-like data
 - End-to-end testing with customer technical team
- Load testing simulation
- UAT with business users

**Phase 4: Production Deployment (Migration Weekend)**
- Deploy policies to production B2C tenant
- Monitor closely during initial batch
- Adjust batch sizes based on performance
- Rollback plan ready if critical issues arise

### 8.3 Rollback Plan

**Triggers for Rollback:**
- Error rate > 15%
- Data corruption detected in CRM/IDM
- Critical functionality broken

**Rollback Procedure:**
1. Stop migration batch processing
2. Revert to previous policy version (keep old policies uploaded)
3. Validate system state
4. Communicate to users
5. Root cause analysis before retry

### 8.4 Policy Version Control

**Naming Convention Update:**
The active LocalAccounts policy set intentionally omits version suffixes in PolicyIds (managed via source control history). If formal versioned promotion is required later, reintroduce suffixes (e.g. `_v1_2_0`) only at release tagging time to avoid excessive file churn during iteration.

**Change Management:**
- All policy changes in Git repository
- Pull request review process
- Automated validation on commit
- Deployment via CI/CD pipeline (Azure DevOps or GitHub Actions)

---

## 9. Migration-Specific Considerations

### 9.1 Legacy Password Validation

**During 6-Month Overlap Period:**
- User signs in with legacy credentials
- B2C calls REST API to validate against ADFS/AD
- On success: Write new password hash to B2C
- On failure: Display error message
- Legacy systems remain read-only

**Technical Profile:**
- `LDAP-Password-Validation-REST`
- Timeout: 10 seconds
- Cache successful validations (session)
- Log all validation attempts

### 9.2 Mass Migration Optimization

**Throttling Mitigation:**
- 3 migration instances (performance-tested scenario)
- 6,000 users per 5-minute batch
- Exponential backoff on 429 errors
- Queue-based processing

**API Usage Pattern:**
- Use Graph API batch operations where possible
- Reuse authentication tokens
- Minimize metadata queries

**Monitoring:**
- Track migration progress in real-time
- Alert on batch failures
- Automatic retry with backoff

---

## 10. Security Considerations

### 10.1 Data Protection

**Sensitive Data Handling:**
- No PII in Application Insights logs
- Use hashed/obfuscated user IDs for correlation
- Secure transmission to CRM (TLS 1.2+)
- API authentication using managed identities or certificates

**Secrets Management:**
- Store API keys in Azure Key Vault
- Reference via policy key containers
- Rotate secrets regularly

### 10.2 API Security

**CRM API Endpoints:**
- Mutual TLS authentication
- IP whitelisting (B2C egress IPs)
- Rate limiting at API gateway level
- Request signing for integrity

**Input Validation:**
- Validate all user inputs in custom policy
- Sanitize data before sending to CRM
- Prevent injection attacks

---

## 11. Documentation Requirements

### 11.1 Technical Documentation

**Policy Documentation:**
- Architecture diagrams (user journey flow, integration points)
- XML policy structure and component relationships
- Technical profile specifications
- Error handling logic flow
- API contracts and response formats

**Operations Runbook:**
- Deployment procedures
- Monitoring and alerting setup
- Common troubleshooting scenarios
- Escalation procedures
- Support contact information

### 11.2 User-Facing Documentation

**End-User Guides:**
- Sign-up process
- Error message interpretations
- Support contact process
- FAQ

**Contoso Transit Operations Team:**
- How to monitor migration progress
- How to interpret dashboards
- When to escalate issues
- Post-migration validation steps

---

## 12. Success Criteria

### 12.1 Functional Requirements

- ✅ User sign-up completes successfully with CRM contact creation
- ✅ No duplicate users created (race condition handled)
- ✅ Errors display on UI banner with context (no blind redirects)
- ✅ CRM API timeouts handled gracefully (no automatic retries)
- ✅ Legacy password validation works during transition period
- ✅ Correlation IDs present in all logs for troubleshooting

### 12.2 Performance Requirements

- ✅ CRM API timeout set to 30 seconds (no premature failures)
- ✅ P95 end-to-end sign-up latency < 15 seconds
- ✅ Support 6,000 user migrations per 5-minute window
- ✅ Error rate < 2% during steady-state operations

### 12.3 User Experience Requirements

- ✅ Clear, actionable error messages in plain language
- ✅ Option to retry from error page (no full journey restart)
- ✅ Support ticket pre-filled with correlation ID
- ✅ No unexpected redirects to Contoso Transit website
- ✅ Consistent UI/UX matching Contoso Transit branding

---

## 13. Risk Management

### 13.1 Identified Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| CRM plugin performance degrades under load | Medium | High | Pre-migration load testing; CRM team optimization; fallback to reduced batch size |
| B2C automatic retry cannot be fully disabled | Low | High | Extend timeout to 30s+; implement idempotency keys; test thoroughly |
| Error wrapping in 200 OK not working | Medium | Medium | Test with multiple B2C versions; consult B2C engineering; alternative error display method |
| Migration throttling exceeds limits | Medium | High | Use tested 3-instance approach; exponential backoff; extended migration window if needed |
| Legacy ADFS validation introduces latency | Low | Medium | Cache validation results; pre-warm connections; monitor and alert |

### 13.2 Contingency Plans

**If CRM API completely fails during migration:**
- Pause migration
- Queue all pending requests
- Resume when CRM service restored
- No data loss due to idempotency

**If B2C policy bugs discovered in production:**
- Revert to previous policy version
- Fix in isolated environment
- Re-deploy after validation

**If throttling limits cause unacceptable delays:**
- Extend migration window
- Negotiate extended data center exit deadline
- Consider tenant sharding (last resort)

---

## 14. Next Steps and Timeline

### 14.1 Immediate Actions (Week 1)

**Identity Engineering Team:**
- [ ] Review custom policy examples related to CT-CASE-001
- [ ] Attempt to reproduce retry issue in isolated environment
- [ ] Consult with B2C product group on timeout/retry configuration options
- [ ] Investigate error wrapping requirement (CT-CASE-002)

**Customer Identity Team:**
- [ ] Share sanitized custom policy XML with engineering team
- [ ] Provide Azure subscription IDs (B2C tenant + migration workload)
- [ ] Share all support case IDs for tracking
- [ ] Document CRM API contract and response formats
- [ ] Provide CRM plugin performance baseline metrics

**Program Coordination:**
- [ ] Follow up with support contacts (sanitized)
- [ ] Coordinate between engineering and customer teams
- [ ] Track progress on all support cases

### 14.2 Development Phases

**Week 1-2: Policy Development**
- Develop base and extension policies
- Implement REST API technical profiles
- Configure error handling and localization
- Unit testing in dev environment

**Week 3: Integration Testing**
- Deploy to test environment
- Integration testing with CRM/IDM
- Performance testing
- Iterate on feedback

**Week 4: Staging and UAT**
- Deploy to staging environment
- End-to-end testing
 - UAT with customer business users
- Load testing simulation

**Week 5: Production Readiness**
- Final policy review and approval
- Deploy to production B2C tenant
- Pre-migration validation
- Operations team training

**Migration Weekend:**
- Execute migration with close monitoring
- Support team on standby
- Real-time adjustments as needed
- Post-migration validation

---

## 15. Appendices

### 15.1 Reference Materials

**Microsoft Documentation:**
- [Azure AD B2C Custom Policies Overview](https://learn.microsoft.com/en-us/azure/active-directory-b2c/custom-policy-overview)
- [Custom Policy Starter Pack](https://github.com/Azure-Samples/active-directory-b2c-custom-policy-starterpack)
- [REST API Technical Profile](https://learn.microsoft.com/en-us/azure/active-directory-b2c/restful-technical-profile)
- [Application Insights Integration](https://learn.microsoft.com/en-us/azure/active-directory-b2c/analytics-with-application-insights)

**Support Cases (Sanitized):**
- CT-CASE-001 - Retry/timeout on CRM contact creation
- CT-CASE-002 - B2C page when an API error occurs
- CT-CASE-003 - Graph API throttling limit

### 15.2 Contact Information (Sanitized)

Personal names intentionally removed. Role-based matrix:

| Group | Primary Role(s) | Responsibilities |
|-------|-----------------|------------------|
| Identity Engineering Team | Identity architect, policy engineer | Custom policy design & escalation |
| Customer Identity Team | Technical lead, developer, support liaison | CRM/IDM integration & functional validation |
| Program Coordination | Program manager | Cross-team coordination & timeline tracking |
| Support Channel | Support engineer (rotation) | Case triage (CT-CASE-001/002/003) |
| Operations Team | Operations lead | Monitoring & runbook execution |

### 15.3 Glossary

- **B2C**: Azure Active Directory Business-to-Consumer
- **IEF**: Identity Experience Framework (custom policies)
- **CRM**: Customer Relationship Management (Dynamics)
- **IDM**: Identity Management system
- **REST**: Representational State Transfer (API)
- **ADFS**: Active Directory Federation Services
- **JIT**: Just-In-Time (migration pattern)
- **P95/P99**: 95th/99th percentile (performance metrics)
- **UAT**: User Acceptance Testing

---

## Document Control

**Version:** 1.0  
**Author:** Identity Architecture Team  
**Last Updated:** October 12, 2025  
**Review Date:** Prior to Phase 1 development start  
**Status:** Draft for Review

**Change History:**
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Oct 12, 2025 | Identity Architecture Team | Initial plan created (sanitized) |

