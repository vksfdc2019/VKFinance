# VK Finance implementation diagrams

These 12 diagrams are embedded beside the relevant sections of the implementation guide. SVG files are editable vector originals; PNG files are rendered at three times the source dimensions for Word. The guide's PDF embeds the vector drawings directly.

| Figure | Diagram | SVG | PNG |
| --- | --- | --- | --- |
| 1 | Portal use cases | [SVG](portal-use-cases.svg) | [PNG](portal-use-cases.png) |
| 2 | Administration use cases | [SVG](administration-use-cases.svg) | [PNG](administration-use-cases.png) |
| 3 | System architecture | [SVG](system-architecture.svg) | [PNG](system-architecture.png) |
| 4 | Core data relationships | [SVG](core-data-relationships.svg) | [PNG](core-data-relationships.png) |
| 5 | Authentication, MFA and first password | [SVG](authentication-flow.svg) | [PNG](authentication-flow.png) |
| 6 | Protected request sequence | [SVG](protected-request-sequence.svg) | [PNG](protected-request-sequence.png) |
| 7 | Ledger posting and void | [SVG](ledger-post-and-void.svg) | [PNG](ledger-post-and-void.png) |
| 8 | EMI accounting | [SVG](emi-accounting.svg) | [PNG](emi-accounting.png) |
| 9 | Daily automation | [SVG](daily-automation.svg) | [PNG](daily-automation.png) |
| 10 | Report execution and scope | [SVG](report-scope.svg) | [PNG](report-scope.png) |
| 11 | Deployment and schedule recovery | [SVG](deployment-lifecycle.svg) | [PNG](deployment-lifecycle.png) |
| 12 | Family onboarding | [SVG](family-onboarding.svg) | [PNG](family-onboarding.png) |

Diagrams summarize the checked-in implementation. Captions in the guide name the source classes. The logical relationship view omits many fields and tenant links; Appendix A supplies the full custom-field dictionary. Use-case associations show capabilities subject to the exact role/action matrix and service rules.

To regenerate both documents, Markdown and diagram assets from the project root:

```powershell
python -m pip install python-docx reportlab pypdf pymupdf
python scripts/build_implementation_document.py
```

The generator uses Calibri from `C:/Windows/Fonts`. Diagram definitions and layout are maintained in [implementation_diagrams.py](../../scripts/implementation_diagrams.py); narrative, placement and document rendering are maintained in [build_implementation_document.py](../../scripts/build_implementation_document.py). Edit these sources before regenerating, since generated SVG/PNG edits will be overwritten.
