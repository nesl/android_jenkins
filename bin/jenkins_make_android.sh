#!/bin/bash
# Author: Kasturi Raghavan (kastur@gmail.com)

# Required args:
# init_tag
# dev_refspec
# local_manifest
# dev_projects
# lunch

DONE_ASCII='
---------------------------------
  ____     ___    _   _   _____ 
 |  _ \   / _ \  | \ | | | ____|
 | | | | | | | | |  \| | |  _|  
 | |_| | | |_| | | |\  | | |___ 
 |____/   \___/  |_| \_| |_____|
---------------------------------'
FAIL_ASCII='
---------------------------------
  _____      _      ___   _     
 |  ___|    / \    |_ _| | |    
 | |_      / _ \    | |  | |    
 |  _|    / ___ \   | |  | |___ 
 |_|     /_/   \_\ |___| |_____|
---------------------------------
LAST 100 LINES OF BUILD LOG (FULL LOG AT URL)' 

set -e
export LANG=en_US.UTF-8  # The default ASCII encoding causes javac errors.

export USE_CCACHE=1
export CCACHE_DIR=/scratch/aosp/ccache
# i.e. adjust permissions to be able to touch CCACHE_DIR, otherwise useless.
touch ${CCACHE_DIR}

PUBLIC_FQDN=$(curl -s \
    http://169.254.169.254/latest/meta-data/public-hostname)
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

# For convenience, print urls of log files.
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
echo SYSTEM STATS: http://${PUBLIC_FQDN}:8000/cgi/dash
echo LOGS: ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/
echo ==USEFUL LOG FILES==
for logfile in repo_init repo_sync_aosp local_manifest.xml repo_sync_nesl \
               repo_dev_checkout build_clean build_real
               #build_api build_clean2
do
  echo ${JOB_URL}ws/logs/${BRANCH_JOB_NUMBERED}/$logfile/'*view*'/
done
echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

set -v

# The LOG_DIR should be unique (i.e. build numbered), but clean to be sure.
rm -rf ${LOG_DIR} 
mkdir -p ${LOG_DIR}

# Log some info about the execution environment.
(env; java -version) > ${LOG_DIR}/info_env

mkdir -p ${BUILD_DIR} 

# Put a symbolic link to this build (w/o build number) in workspace.
rm -f $WORKSPACE/${BRANCH_JOB}
ln -s ${BUILD_DIR} $WORKSPACE/${BRANCH_JOB}

cd ${BUILD_DIR}

# Remove .repo/local_manifest.xml and .repo/local_manifests directory.
rm -rf .repo/local_manifest*

test ${FLAG_NO_SYNC} == "true" || ( \
$ANNOTATE $REPO init -u $MIRROR/platform/manifest.git -b ${init_tag} \
    >${LOG_DIR}/repo_init 2>&1; \
$ANNOTATE $REPO sync -j8 >${LOG_DIR}/repo_sync_aosp 2>&1; \
mkdir .repo/local_manifests; \
echo "${local_manifest}" | tee -a ${LOG_DIR}/override.xml \
    > .repo/local_manifests/override.xml; \
$ANNOTATE $REPO sync -j8 >${LOG_DIR}/repo_sync_nesl 2>&1;

$REPO forall $dev_projects \
    -c 'git checkout $(git rev-parse $dev_refspec)' \
    >${LOG_DIR}/repo_dev_checkout 2>&1; \
)

mkdir ${LOG_DIR}/diffs

$REPO forall $dev_projects \
    -c "LOG_DIR=${LOG_DIR} /aosp/bin/jenkins_make_android_diff.sh"

( \
  ls -la; \
  $REPO forall -c 'echo $REPO_PROJECT && git log -n1 && echo "======"' \
) > ${LOG_DIR}/info_tree 2>&1

set +v

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-==
source build/envsetup.sh
prebuilts/misc/linux-x86/ccache/ccache -M 100G
lunch $lunch

# Log execution environment after lunch.
( \
  env; \
  java -version; \
  echo "======"; \
  /aosp/golden_clone/prebuilts/misc/linux-x86/ccache/ccache -s; \
) > ${LOG_DIR}/info_lunch_env 2>&1

echo -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
set -v -e

test ${FLAG_NO_CLOBBER} == "true" || \
    $ANNOTATE make clobber >${LOG_DIR}/build_clean 2>&1

test ${FLAG_UPDATE_API} == "false" ||  
    $ANNOTATE make update-api >${LOG_DIR}/build_api 2>&1

# Build android for real.
set +e
$ANNOTATE make -j16 >${LOG_DIR}/build_real 2>&1 

ret_code=$?
set -e
if [ $ret_code != 0 ]; then
  echo ${FAIL_ASCII}
  tail -n100 ${LOG_DIR}/build_real
  exit 1
fi

# Since we have 'set -e', SUCCESSFUL will only be created if above succeeds.
touch ${LOG_DIR}/SUCCESSFUL
echo ${DONE_ASCII}

# Finally, copy the 'out/' folder over to workspace,
# i.e. make sure this is persistent storage on EBS, not ephermeral.
mkdir -p ${COPY_DIR}
cp -r out ${COPY_DIR}
touch ${LOG_DIR}/SUCCESSFUL-COPY
