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
disable_tx=0
keep_mitm_running=0
while [ "$1" != "" ]; do
    case $1 in
        --changed-only) changed_only=1
                        ;;
        --debug)        output_redirect=""
                        ;;
        --no-tx)        disable_tx=1
                        ;;
        --inspect-tx)   keep_mitm_running=1
                        ;;
        *)              echo "Usage: $0 [--changed-only] [--debug] [--no-tx] [--inspect-tx]"
                        exit 1
                        ;;
    esac
    shift
done

if [[ $disable_tx == 0 ]]; then
  source /scripts/checktx.sh
  if [[ $disable_tx == 1 ]]; then
    echo -e "\033[0;33mtx.fhir.org couldn't be reached. Disabling terminology server checking.\033[0m"
  fi
fi

if [[ $disable_tx == 1 ]]; then
  if [[ $keep_mitm_running == 1 ]]; then
    echo "You requested to inspect the terminology server, but terminology checking is disabled, so I'll just refuse."
  fi
  tx_opt="-tx n/a"
else
  tx_opt="-proxy 127.0.0.1:8080 -tx http://v4.combined.tx"

  # Start the proxy server to intelligently handle terminology requests
  set -m
  mitmweb --web-host "0.0.0.0" -s /tools/CombinedTX/CombinedTX.py -q &
  echo -e "\033[0;33mYou can spy on the terminology server log at http://localhost:8081\033[0m"
fi

source /scripts/getresources.sh

# Run the HL7 Validator and analyze the output. Parameters:
# $1: textual description of the resources being analyzed
# $2: list of files to analyze (remember to quote them in case the list is empty)
# $3: optional profile canonical to validate the resources against
validate() {
  echo
  if [[ $2 =~ ^[^\s]*$ ]]; then
    echo -e "\033[1;37m+++ No $1 to check\033[0m"
  else
    echo -e "\033[1;37m+++ Validating $1\033[0m"
    local output=$output_dir/validate-${1//[^[:alnum:]]/}.xml
    if [[ -n $3 ]]; then
      local profile_opt="-profile $3"
    fi
    eval java -jar $tools_dir/validator/validator.jar -version 4.0 -ig qa/ -ig resources/ -recurse $profile_opt $tx_opt $2 -output $output $output_redirect
    if [ $? -eq 0 ]; then
      python3 $tools_dir/hl7-fhir-validator-action/analyze_results.py --colorize --fail-at error --ignored-issues known-issues.yml $output
      if [[ $disable_tx == 1 ]]; then
        echo -e "\033[0;33m(No terminology server was used)\033[0m"
      fi
    else
      echo -e "\033[0;33mThere was an error running the validator. Re-run with the --debug option to see the output.\033[0m"
    fi
    if [ $? -ne 0 ]; then
      exit_code=1
    fi
  fi
}

# Perform all HL7 Validator actions
validate "zib profiles" "$zib_profiles" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions-Zib-Profiles"
validate "zib extensions" "$zib_extensions" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions-Zib-Extensions"
validate "nl-core profiles" "$nlcore_profiles" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions-NlCore-Profiles"
validate "nl-core extensions" "$nlcore_extensions" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions-NlCore-Extensions"
validate "other profiles" "$other_profiles" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-StructureDefinitions"
validate "ConceptMaps" "$conceptmaps" "http://nictiz.nl/fhir/StructureDefinition/ProfilingGuidelinesR4-ConceptMaps"
validate "other terminology" "$other_terminology"
validate "examples" "$examples"

# Run zib compliance tool
echo
echo -e "\033[1;37m+++ Checking zib compliance\033[0m"
if [[ -z $zib_profiles ]]; then
  echo "No input, skipping"
else
  echo "Generating snapshots"
  eval /scripts/generatezibsnapshots.sh $zib_profiles $zib_extensions $output_redirect

  if [ $? -eq 0 ]; then
    if [[ $changed_only == 0 ]]; then
      check_missing="mapped-only"
    else
      check_missing="none"
    fi
    node $tools_dir/zib-compliance-fhir/index.js -m qa/zibs2020.max -z 2020 -l 2 --check-missing=$check_missing -f text --fail-at warning --zib-overrides known-issues.yml snapshots/*json
  else
    echo -e "\033[0;33mThere was an error during snapshot generation. Re-run with the --debug option to see the output.\033[0m"
    echo "Skipping zib compliance check."
  fi
  if [ $? -ne 0 ]; then
    exit_code=1
  fi
fi

if [[ $keep_mitm_running == 1 ]]; then
  echo
  echo "Bringing proxxy server to foreground. Press Ctrl+C to finish."
  fg > /dev/null
fi

exit $exit_code