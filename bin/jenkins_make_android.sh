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
export CCACHE_DIR=/scratch/aosp/ccache

touch ${CCACHE_DIR}  # If we can't touch it, then the ccache is useless!
# i.e. adjust permissions to be able to touch CCACHE_DIR.

PUBLIC_FQDN=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
JOB_URL=http://${PUBLIC_FQDN}:8080/job/${JOB_NAME}/
REPO='/aosp/bin/repo'
#ANNOTATE="annotate-output +%Y-%m-%d-%H:%M:%S.%N"
ANNOTATE=
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
               repo_dev_checkout build_clean build_real
               #build_api build_clean2
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
rm -f .repo/local_manifest*

#rm -rf $dev_projects

$ANNOTATE $REPO init -u $MIRROR/platform/manifest.git -b ${init_tag} \
    >${LOG_DIR}/repo_init 2>&1
$ANNOTATE $REPO sync -j8 >${LOG_DIR}/repo_sync_aosp 2>&1

echo "${local_manifest}" | tee -a ${LOG_DIR}/local_manifests \
    > .repo/local_manifests
$ANNOTATE $REPO sync -j8 >${LOG_DIR}/repo_sync_nesl 2>&1
$ANNOTATE $REPO forall $dev_projects \
    -c 'git checkout $(git rev-parse $dev_refspec)' \
    >${LOG_DIR}/repo_dev_checkout 2>&1
set +v +x

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
ls -la

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
source build/envsetup.sh
lunch $lunch
env
java -version
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
set -v -e
$ANNOTATE make clobber >${LOG_DIR}/build_clean 2>&1
#$ANNOTATE make j8 update-api >${LOG_DIR}/build_api 2>&1
#$ANNOTATE make clobber >${LOG_DIR}/build_clean2 2>&1
$ANNOTATE make -j20 >${LOG_DIR}/build_real 2>&1
touch ${LOG_DIR}/SUCCESSFUL

mkdir -p ${COPY_DIR}
cp -r out ${COPY_DIR}
touch ${LOG_DIR}/SUCCESSFUL-COPY
