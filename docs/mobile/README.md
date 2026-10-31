# Owner Workspace — mobile documentation

The Owner Workspace lets the platform owner open any family and work inside it from the **Salesforce mobile app** (or desktop Lightning). It runs inside the VK Finance Console, signs in with Salesforce, and reuses every rule of the portal's Apex services.

| Document                                        | For                                                                                   |
| ----------------------------------------------- | ------------------------------------------------------------------------------------- |
| [Architecture review](Architecture_Review.md)   | Why this design, the options considered, security model, risks and decisions          |
| [Implementation guide](Implementation_Guide.md) | Setting it up: deploy, permissions, Salesforce mobile app, first use, troubleshooting |
| [Components directory](Components_Directory.md) | Every Apex class, LWC, tab and metadata change, with its job and dependencies         |
| [Technical reference](Technical_Reference.md)   | Controller API, data shapes, design tokens, testing, and how to extend it             |

## Release status

| Item                                                       | State                                                                                                                     |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Apex (`OwnerContext`, `VkfOwnerController`, audit tagging) | Built; 13 Apex tests                                                                                                      |
| Lightning Web Components (9 bundles)                       | Built; 26 Jest tests passing, ESLint clean                                                                                |
| Console app enabled for phones, new tab, permission set    | Built                                                                                                                     |
| Org validation (dry run, all local tests)                  | **Passed**: 17/17 components, 196/196 Apex tests — see [Validation evidence](Implementation_Guide.md#validation-evidence) |
| Deployment to the `VKFinance` org                          | **Deployed 31 Oct 2026** (`0AfjV000005RitKSAS`): 17/17 components, 196/196 Apex tests                                     |
| Physical phone check (Android/iOS Salesforce app)          | Pending after deployment                                                                                                  |
