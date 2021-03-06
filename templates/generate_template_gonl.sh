#!/bin/bash

module load NGS_DNA/3.4.0
module list 
HOST=$(hostname)
thisDir=$(pwd)

ENVIRONMENT_PARAMETERS="parameters_${HOST%%.*}.csv"
TMPDIRECTORY=$(basename $(cd ../../ && pwd ))
GROUP=$(basename $(cd ../../../ && pwd ))

PROJECT=projectXX
WORKDIR="/groups/${GROUP}/${TMPDIRECTORY}"
RUNID=runXX

## Normal user, please leave BATCH at _chr
## For expert modus: small batchsize (6) fill in '_small'  or per chromosome fill in _chr
BATCH="_b38_chr"
samplesheet=${WORKDIR}/generatedscripts/${PROJECT}/${PROJECT}.csv
mac2unix $samplesheet

python ${EBROOTNGS_DNA}/scripts/samplesize.py ${samplesheet} $thisDir
SAMPLESIZE=$(cat externalSampleIDs.txt | uniq | wc -l)

python ${EBROOTNGS_DNA}/scripts/gender.py $samplesheet
var=$(cat ${samplesheet}.tmp | wc -l)

if [ $var != 0 ]
then
    	mv ${samplesheet}.tmp ${samplesheet}
        echo "samplesheet updated with Gender column"
fi
echo "Samplesize is $SAMPLESIZE"

if [ $SAMPLESIZE -gt 199 ]
then
    	WORKFLOW=${EBROOTNGS_DNA}/workflow_samplesize_bigger_than_200.csv
else
        WORKFLOW=${EBROOTNGS_DNA}/workflow_gonl.csv
fi

if [ -f .compute.properties ];
then
     rm .compute.properties
fi

if [ -f ${WORKDIR}/generatedscripts/${PROJECT}/out.csv ];
then
    	rm -rf ${WORKDIR}/generatedscripts/${PROJECT}/out.csv
fi

echo "tmpName,${TMPDIRECTORY}" > ${WORKDIR}/generatedscripts/${PROJECT}/tmpdir_parameters.csv 

perl ${EBROOTNGS_DNA}/scripts/convertParametersGitToMolgenis.pl ${WORKDIR}/generatedscripts/${PROJECT}/tmpdir_parameters.csv > \
${WORKDIR}/generatedscripts/${PROJECT}/tmpdir_parameters_converted.csv

perl ${EBROOTNGS_DNA}/scripts/convertParametersGitToMolgenis.pl ${EBROOTNGS_DNA}/parameters_gonl.csv > \
${WORKDIR}/generatedscripts/${PROJECT}/out.csv

perl ${EBROOTNGS_DNA}/scripts/convertParametersGitToMolgenis.pl ${EBROOTNGS_DNA}/parameters_${GROUP}.csv > \
${WORKDIR}/generatedscripts/${PROJECT}/group_parameters.csv

perl ${EBROOTNGS_DNA}/scripts/convertParametersGitToMolgenis.pl ${EBROOTNGS_DNA}/${ENVIRONMENT_PARAMETERS} > \
${WORKDIR}/generatedscripts/${PROJECT}/environment_parameters.csv

sh $EBROOTMOLGENISMINCOMPUTE/molgenis_compute.sh \
-p ${WORKDIR}/generatedscripts/${PROJECT}/out.csv \
-p ${WORKDIR}/generatedscripts/${PROJECT}/group_parameters.csv \
-p ${WORKDIR}/generatedscripts/${PROJECT}/environment_parameters.csv \
-p ${WORKDIR}/generatedscripts/${PROJECT}/tmpdir_parameters_converted.csv \
-p ${EBROOTNGS_DNA}/batchIDList${BATCH}.csv \
-p ${WORKDIR}/generatedscripts/${PROJECT}/${PROJECT}.csv \
-w ${EBROOTNGS_DNA}/create_external_samples_ngs_projects_workflow.csv \
-rundir ${WORKDIR}/generatedscripts/${PROJECT}/scripts \
--runid ${RUNID} \
-o "workflowpath=${WORKFLOW};\
outputdir=scripts/jobs;mainParameters=${WORKDIR}/generatedscripts/${PROJECT}/out.csv;\
group_parameters=${WORKDIR}/generatedscripts/${PROJECT}/group_parameters.csv;\
groupname=${GROUP};\
ngsversion=$(module list | grep -o -P 'NGS_DNA(.+)');\
environment_parameters=${WORKDIR}/generatedscripts/${PROJECT}/environment_parameters.csv;\
tmpdir_parameters=${WORKDIR}/generatedscripts/${PROJECT}/tmpdir_parameters_converted.csv;\
batchIDList=${EBROOTNGS_DNA}/batchIDList${BATCH}.csv;\
worksheet=${WORKDIR}/generatedscripts/${PROJECT}/${PROJECT}.csv" \
-weave \
--generate

