#!/bin/bash

exit_with_message () {
  echo $1 >&2
  exit 1
}

for dependency in "jq" "fhir4"
do
    if ! [ -x "$(command -v $dependency)" ]; then
        exit_with_message "$dependency is not installed."
    fi
done

fhirCommand="fhir4"

$fhirCommand login

echo -n "FHIR package name: "
read packageName
if [ -z "$packageName" ]; then
    exit_with_message "It's mandatory to specify the name of a FHIR package. Exiting..."
fi

echo -n "FHIR package version (latest): "
read packageVersion
if [ -z "$packageVersion" ]; then
    packageVersion=$($fhirCommand versions $packageName --raw | jq -r '."dist-tags"."latest"')
fi

echo -n "Upload package to FHIR server: "
read fhirServer
if [ -z "$fhirServer" ]; then
    exit_with_message "It's mandatory to specify the endpoint of a FHIR server. Exiting..."
fi
$fhirCommand server add $fhirServer $fhirServer | awk '{ print "\t" $0 }'

echo "Checking if $fhirServer/metadata can be reached"
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

echo "Installing FHIR package '$packageName' using version $packageVersion"
$fhirCommand install $packageName $packageVersion | awk '{ print "\t" $0 }'

echo "Checking if FHIR '$packageName' using version $packageVersion was successfully installed"
$fhirCommand cache | grep -q $packageName#$packageVersion
if [ $? -eq 1 ]; then
    exit_with_message "Failed to install package $packageName using version $packageVersion"
else
    echo -e "\t Successfully found package '$packageName' with version '$packageVersion' in cache"
fi

canonicals=$($fhirCommand canonicals $packageName $packageVersion)
for canonical in $canonicals; do
    echo -e "\nTrying to resolve $canonical..."
    $fhirCommand resolve $canonical | awk '{ print "\t" $0 }'
    json=$($fhirCommand show --json)

    resourceType=$(echo $json | jq -r '.resourceType')
    echo "Uploading $canonical ($resourceType) to $fhirServer"

    # Should we do a PUT or POST?
    id=$(echo $json | jq -r -e '.id')
    if [ $? = 1 ]; then
        $fhirCommand post $fhirServer | awk '{ print "\t" $0 }'
    else
        echo "$id"
        $fhirCommand put $fhirServer | awk '{ print "\t" $0 }'
    fi
done