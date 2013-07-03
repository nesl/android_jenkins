#!/bin/bash
# Author: Kasturi Raghavan (kastur@gmail.com)

# Required args:
# kernel_project, aosp_branch
# local_manifest, nesl_branch
# arch, cross_compile, defconfig

set -e
REPO='/aosp/bin/repo --trace'
ANNOTATE="annotate-output +%Y-%m-%d-%H:%M:%S.%N"
MIRROR=/aosp/kernels_mirror

# Replace "/" since we don't want to create nested directories.
BRANCH_JOB="${JOB_NAME}-${nesl_branch////_}"
BRANCH_JOB_NUMBERED=${BRANCH_JOB}-${BUILD_NUMBER}
LOG_DIR=$WORKSPACE/logs/${BRANCH_JOB_NUMBERED}
BUILD_DIR=/scratch/aosp/${BRANCH_JOB}
COPY_DIR=$WORKSPACE/copy/${BRANCH_JOB_NUMBERED}

# For convenience, print out log file urls.
echo ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/
for logfile in repo_init repo_sync_aosp local_manifest.xml repo_sync_nesl \
               git_aosp_checkout git_nesl_checkout build_config build
do
  echo ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/$logfile/'*view*'/
done

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
env
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

set -v -x
rm -rf ${LOG_DIR} 
mkdir -p ${LOG_DIR}

mkdir -p ${BUILD_DIR} 
rm -f $WORKSPACE/${BRANCH_JOB}
ln -s ${BUILD_DIR} $WORKSPACE/${BRANCH_JOB}
cd ${BUILD_DIR}

$ANNOTATE $REPO init -u $MIRROR/platform/manifest.git 2>&1 >>${LOG_DIR}/repo_init

$ANNOTATE $REPO sync -j8 2>&1 >>${LOG_DIR}/repo_sync_aosp
$ANNOTATE $REPO forall ${kernel_project} \
  -c 'git checkout $(git rev-parse $aosp_branch)' 2>&1 >>${LOG_DIR}/git_aosp_checkout

echo "${local_manifest}" | tee -a ${LOG_DIR}/local_manifest.xml > .repo/local_manifest.xml
$ANNOTATE $REPO sync -j8 2>&1 >>${LOG_DIR}/repo_sync_nesl
$ANNOTATE $REPO forall ${kernel_project} \
  -c 'git checkout $(git rev-parse $nesl_branch)' 2>&1 >>${LOG_DIR}/git_nesl_checkout
set +v +x

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
ls -la

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

set -v -e
export PATH=$(pwd)/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6/bin:$PATH
cd ${kernel_project}
export ARCH=${arch}
export SUBARCH=${arch}
export CROSS_COMPILE=${cross_compile}
$ANNOTATE make $defconfig 2>&1 >>${LOG_DIR}/build_config
$ANNOTATE make -j16 2>&1 >>${LOG_DIR}/build
touch ${LOG_DIR}/SUCCESSFUL

mkdir -p ${COPY_DIR}
cp -r arch ${COPY_DIR}
touch ${LOG_DIR}/SUCCESSFUL-COPY
