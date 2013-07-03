#!/bin/bash
# Author: Kasturi Raghavan (kastur@gmail.com)

# Required args:
# init_tag
# dev_refspec
# local_manifest
# dev_projects
# lunch

set -e
export LANG=en_US.UTF-8  # The default ASCII encoding results in javac errors.
export USE_CCACHE=1
export CCACHE_DIR=/aosp/ccache
PUBLIC_FQDN=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
JOB_URL=http://${PUBLIC_FQDN}:8080/job/${JOB_NAME}/
REPO='/aosp/bin/repo --trace'
ANNOTATE="annotate-output +%Y-%m-%d-%H:%M:%S.%N"
MIRROR=/aosp/mirror

# Replace "/" since we don't want to create nested directories.
BRANCH_JOB="${JOB_NAME}-${dev_refspec////_}"
BRANCH_JOB_NUMBERED=${BRANCH_JOB}-${BUILD_NUMBER}
LOG_DIR=$WORKSPACE/logs/${BRANCH_JOB_NUMBERED}
BUILD_DIR=/scratch/aosp/${BRANCH_JOB}
COPY_DIR=$WORKSPACE/copy/${BRANCH_JOB_NUMBERED}

# For convenienve, print urls of log files.
echo ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/
for logfile in repo_init repo_sync_aosp local_manifest.xml repo_sync_nesl \
               repo_dev_checkout build_clean build
do
  echo ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/$logfile/'*view*'/
done

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
env
java -version
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

set -v -x

rm -rf ${LOG_DIR} 
mkdir -p ${LOG_DIR}

mkdir -p ${BUILD_DIR} 
rm -f $WORKSPACE/${BRANCH_JOB}
ln -s ${BUILD_DIR} $WORKSPACE/${BRANCH_JOB}

cd ${BUILD_DIR}

$ANNOTATE $REPO init -u $MIRROR/platform/manifest.git -b ${init_tag} 2>&1 \
    >>${LOG_DIR}/repo_init
$ANNOTATE $REPO sync -j8 2>&1 >>${LOG_DIR}/repo_sync_aosp

echo "${local_manifest}" | tee -a ${LOG_DIR}/local_manifest.xml \
    > .repo/local_manifest.xml
$ANNOTATE $REPO sync -j8 2>&1 >>${LOG_DIR}/repo_sync_nesl
$ANNOTATE $REPO forall $dev_projects \
    -c 'git checkout $(git rev-parse $dev_refspec)' \
    2>&1 >>${LOG_DIR}/repo_dev_checkout
set +v +x

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
ls -la

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

source build/envsetup.sh
lunch $lunch

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
set -v -e
$ANNOTATE make clobber 2>&1 >>${LOG_DIR}/build_clean
$ANNOTATE make update-api -j16 2>&1 >>${LOG_DIR}/build
$ANNOTATE make -j16 2>&1 >>${LOG_DIR}/build
touch ${LOG_DIR}/SUCCESSFUL

mkdir -p ${COPY_DIR}
cp -r out ${COPY_DIR}
touch ${LOG_DIR}/SUCCESSFUL-COPY
