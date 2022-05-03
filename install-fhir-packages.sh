#!/bin/bash

exit_with_message () {
  echo $1 >&2
  exit 1
}

check_availability_metadata () {
    echo -e "\nChecking if $fhirServer/metadata can be reached"
    endpointSucccess=$(curl -sL -w '%{http_code}' "$fhirServer/metadata" -o /dev/null)
    if [ $endpointSucccess != "200" ]; then
        echo "Could not reach FHIR server $fhirServer"
        echo "Continue anyway (Y/n)?"
        read forcePackageInstall

        forcePackageInstall=${forcePackageInstall:-y}
        forcePackageInstall=$(echo "$forcePackageInstall" | awk '{print tolower($0)}')

        if [ "$forcePackageInstall" = "n" ] || [ "$forcePackageInstall" != "y" ]; then
            exit_with_message "Exiting..."
        fi
    else
        echo -e "\t Successfully reached $fhirServer"
    fi
}

# ------
# Setup
# ------

for dependency in "jq" "fhir"
do
    if ! [ -x "$(command -v $dependency)" ]; then
        exit_with_message "$dependency is not installed."
    fi
done

fhirCommand="fhir"
$fhirCommand login

echo -n "FHIR package name: "
read packageName
if [ -z "$packageName" ]; then
    exit_with_message "It's mandatory to specify the name of a FHIR package. Exiting..."
fi

echo -n "FHIR package version (latest): "
read packageVersion

rawOutputVersions=$($fhirCommand versions $packageName --raw)
if [ -z "$packageVersion" ]; then
    packageVersion=$(echo $rawOutputVersions | jq -r '."dist-tags"."latest"')
fi
fhirVersion=$(echo $rawOutputVersions | jq -r ".versions.\"$packageVersion\".fhirVersion" | awk '{print tolower($0)}')
fhir spec $fhirVersion --project

echo -n "Upload package to FHIR server: "
read fhirServer
if [ -z "$fhirServer" ]; then
    exit_with_message "It's mandatory to specify the endpoint of a FHIR server. Exiting..."
fi
$fhirCommand server add $fhirServer $fhirServer | awk '{ print "\t" $0 }'

check_availability_metadata

echo -e "\nInstalling FHIR package '$packageName' using version $packageVersion"

if [ ! -f "package.json" ]; then
    fhir init
fi

$fhirCommand install $packageName $packageVersion | awk '{ print "\t" $0 }'

echo -e "\nChecking if FHIR '$packageName' using version $packageVersion was successfully installed"
$fhirCommand cache | grep -q $packageName#$packageVersion
if [ $? -eq 1 ]; then
  $fhirCommand cache | grep -q $packageName@$packageVersion # Re-try with @ instead of # as the separator
fi

if [ $? -eq 1 ]; then
    exit_with_message "Failed to install package $packageName using version $packageVersion"
else
    echo -e "\t Successfully found package '$packageName' with version '$packageVersion' in cache"
fi

# ----------------------------
# Upload conformance resource
# ----------------------------

canonicals=$($fhirCommand canonicals $packageName $packageVersion)
for canonical in $canonicals; do
    echo -e "\nTrying to resolve $canonical..."
    $fhirCommand resolve $canonical | awk '{ print "\t" $0 }'
    json=$($fhirCommand show --output json)

    resourceType=$(echo $json | jq -r '.resourceType')
    echo -e "\tUploading $canonical ($resourceType) to $fhirServer"

    # Should we do a PUT or POST?
    id=$(echo $json | jq -r -e '.id')
    if [ $? = 1 ]; then
        $fhirCommand post $fhirServer | awk '{ print "\t" $0 }'
    else
        $fhirCommand put $fhirServer | awk '{ print "\t" $0 }'
    fi
done

echo "Successfully uploaded package '$packageName' using version $packageVersion to $fhirServer"

# ----------------
# Upload examples
# ----------------

echo -e "\nUpload example resources from FHIR package '$packageName' using version $packageVersion (Y/n)?"
read installExamples

echo -n "Upload examples to FHIR server: "
read fhirServer
if [ -z "$fhirServer" ]; then
    exit_with_message "It's mandatory to specify the endpoint of a FHIR server. Exiting..."
fi
$fhirCommand server add $fhirServer $fhirServer | awk '{ print "\t" $0 }'

check_availability_metadata

installExamples=${installExamples:-y}
installExamples=$(echo "$installExamples" | awk '{print tolower($0)}')

if [ "$installExamples" = "n" ] || [ "$installExamples" != "y" ]; then
    exit_with_message "Exiting..."
fi

currentWorkingDir=$(pwd)
fhirCacheLocation=$($fhirCommand cache --location)
cd $fhirCacheLocation
cd $packageName#$packageVersion/package/examples
$fhirCommand push .
while true; do

    currentResource=$(fhir peek || true)
    if [[ "$currentResource" == *"The stack is empty."* ]]; then
        echo "Uploaded all example FHIR resources to $fhirServer"
        break
    fi

    echo "Uploading $currentResource ..."
    json=$($fhirCommand show --output json)
    id=$(echo $json | jq -r -e '.id')
    if [ $? = 1 ]; then
        $fhirCommand post $fhirServer | awk '{ print "\t" $0 }'
    else
        $fhirCommand put $fhirServer | awk '{ print "\t" $0 }'
    fi

done