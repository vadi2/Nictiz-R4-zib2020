- Renamed extensions for MedicationAdministration2 and MedicationUse to also include the '2'.
- Removed refernce to HL7 base resource in the ext-MedicationUse2.Prescriber extension.
- Added guidance and implicit mappings on MedicationDispense.status on how to deal with the mandatory status element (#122).
- Added guidance on how to deal with MedicationDispense.inten (#127).
- Added extension for FinancialIndicationCode concept in nl-core-DispenseRequest (#106). 
- Added SearchParameters to nl-core folder, created based on new Profiling Guidelines (#139).
- Improved guidance on StopType and mapped StopType to ModifierExtension in MedicationUse too (#114).
- Added extensions with mapping of 'RelatieZorgepisode' in MedicationAgreement and DispenseRequest (#105) and removed previously made implicit mappings for EpisodeOfCare.