#!/bin/bash

work_dir=/workdir
src_dir=/repo
tools_dir=/tools
output_dir=/output

exit_code=0

# The repo is mounted read-only, we make a local copy to src_dir where we can modify things if needed.
rm -rf $work_dir # The assumption is that we use run in a temp container, but for good measure, lets erase the target location first.
rm $output_dir/* 2> /dev/null
cp -r $src_dir $work_dir
cd $work_dir

changed_only=0
output_redirect="> /dev/null 2> /dev/null"
while [ "$1" != "" ]; do
    case $1 in
        --changed-only) shift
                        changed_only=1
                        ;;
        --debug)        shift
                        output_redirect=""
                        ;;
        *)              echo "Usage: $0 [--changed-only] [--debug]"
                        exit 1
                        ;;
    esac
    shift
done

source /scripts/getresources.sh
source /scripts/mkprofilingig.sh

# Run the HL7 Validator and analyze the output. Parameters:
# $1: textual description of the resources being analyzed
# $2: list of files to analyze (remember to quote them in case the list is empty)
# $3: optional profile canonical to validate the resources against
validate() {
  echo
  echo "+++ Validating $1"
  if [[ -z $2 ]]; then
    echo "No input, skipping"
  else
    local output=$output_dir/validate-${1//[^[:alnum:]]/}.xml
    if [[ -n $3 ]]; then
      local profile_opt="-profile $3"
      echo $profile_opt
    fi
    eval java -jar $tools_dir/validator/validator.jar -version 4.0 -ig ig/ -recurse $profile_opt $2 -output $output $output_redirect
    if [ $? -eq 0 ]; then
      python3 $tools_dir/hl7-fhir-validator-action/analyze_results.py --fail-at warning --ignored-issues known-issues.yml $output
    else
      echo "There was an error running the validator. Re-run with the --debug option to see the output."
    fi
    if [ $? -ne 0 ]; then
      exit_code=1
    fi
  fi
}

validate "zib profiles" "$zib_profiles" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions-Zib"
validate "other profile" "$other_profiles" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions"
validate "ConceptMaps" "$conceptmaps" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-ConceptMaps"
validate "examples" "$examples"

echo
echo "+++ Checking zib compliance"
if [[ -z $zib_profiles ]]; then
  echo "No input, skipping"
else
  echo "Generating snapshots"
  eval /scripts/generatezibsnapshots.sh $zib_profiles $output_redirect

  if [ $? -eq 0 ]; then
    node $tools_dir/zib-compliance-fhir/index.js -m qa/zibs2020.max -z 2020 -r -l 2 -f text --fail-at warning --zib-overrides known-issues.yml snapshots/*json
  else
    echo "There was an error during snapshot generation. Re-run with the --debug option to see the output."
    echo "Skipping zib compliance check."
  fi
  if [ $? -ne 0 ]; then
    exit_code=1
  fi
fi

exit $exit_code